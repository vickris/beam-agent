defmodule BeamAgent.API do
  @moduledoc """
  Public API for executing agents.

  ## Lifecycle and supervision

  `run/2` starts one `BeamAgent.Runner` under `BeamAgent.RunSupervisor` (a
  `DynamicSupervisor`) and blocks the calling process until it gets a
  result. Each run is an independent, unregistered `GenServer` — any number
  of runs can be in flight concurrently, and one crashing (e.g. a tool
  raising) has no effect on any other; it's caught here via
  `Process.monitor/1` and turned into a `BeamAgent.Run.crash/2` result
  rather than propagating to the caller.

  There are two layers of time enforcement, and they can race:

    * `BeamAgent.Guardrails`' `MaxExecutionTime` check runs *between* steps
      and tool calls — it's graceful, and produces a normal
      `{:max_execution_time_reached, ...}` failure once the runner notices.
    * A tool call itself can't be preempted mid-execution (e.g. a tool that
      blocks on I/O far longer than the guardrail's limit). `run/2` is the
      backstop for that: it waits `max_execution_time_ms + @timeout_grace_ms`
      and, if the runner still hasn't replied, force-terminates it via
      `DynamicSupervisor.terminate_child/2` and returns a
      `BeamAgent.Run.timeout/2` result instead.

  The grace period exists so the graceful path normally wins the race —
  see the `@timeout_grace_ms` doc below.

  ## Run telemetry

  `run/2` emits `[:beam_agent, :run, :start]` and then `:stop` on a normal
  return, or `:exception` when an error, throw, or exit escapes the API.
  Handled failures, including runner crashes and timeouts, emit `:stop`.
  External process termination can prevent a terminal event from being emitted.

  All events carry the same opaque `:run_id` and `:telemetry_span_context`.
  Start measurements are `:system_time` and `:monotonic_time`. Terminal
  measurements are `:duration` and `:monotonic_time`, in native time units.
  Duration covers the API boundary, including verification and timeout cleanup,
  and is measured independently of `Run.duration_ms`. Stop events also include
  integer `:iterations` and `:tool_calls` measurements when available.

  Stop metadata includes `:outcome` (`:ok` or `:error`), `:execution_status`
  (`:finished`, `:failed`, or `:unknown`), and `:verification_status` (`:passed`,
  `:failed`, `:not_run`, or `:unknown`). Failures include an `:error_type`:
  `:startup_failed`, `:verification_failed`, `:execution_failed`,
  `:runner_crashed`, `:execution_timeout`, `:unknown_tool`,
  `:max_iterations_reached`, `:max_tool_calls_reached`,
  `:max_execution_time_reached`, `:max_context_messages_exceeded`,
  `:context_limit_too_small`, or `:unexpected_result`.

  Exception metadata contains only the correlation fields, `:error_type` set
  to `:exception`, and `:kind` (`:error`, `:throw`, or `:exit`). The original
  exception is re-raised unchanged. Execution content, raw errors, and
  stacktraces are never included in telemetry.
  """

  alias BeamAgent.Run
  alias BeamAgent.RunSupervisor
  alias BeamAgent.Runner
  alias BeamAgent.Telemetry

  # Extra time given to the runner beyond its own `:max_execution_time_ms`
  # guardrail before the API gives up on it. The guardrail is only checked
  # between steps/tool calls, so a run can overshoot it by roughly one
  # step's duration before the runner notices and replies on its own; this
  # grace period lets that graceful `:max_execution_time_reached` failure
  # win the race. The receive timeout below is a backstop for a runner
  # that is genuinely stuck, not the primary enforcement mechanism.
  @timeout_grace_ms 1_000

  @doc """
  Runs `goal` to completion (or failure) and returns `{:ok, run}` or
  `{:error, run}`, where `run` is always a `BeamAgent.Run.t()`.

  `{:ok, run}` only when the runner finished *and* verification passed;
  every other outcome (a guardrail tripped, an unknown tool was called, the
  hard timeout fired, the runner crashed, or verification failed a
  plausible-looking finish) comes back as `{:error, run}` with
  `run.error`/`run.verification_error` set accordingly.

  ## Options

    * `:llm` (required) — `{module, opts}`, where `module` implements
      `BeamAgent.LLM.Client`.
    * `:tools` — `%{atom() => module}` of tools available to this run, each
      module implementing `BeamAgent.Tools.Behaviour`. Defaults to `%{}`; a
      tool call for a name not in this map fails with `:unknown_tool`.
    * `:guardrails` — keyword opts consumed by `BeamAgent.Guardrails` (see
      its submodules for individual keys/defaults, e.g.
      `:max_execution_time_ms`, `:max_iterations`, `:max_context_messages`,
      `:max_tool_calls`).
    * `:verification` — keyword opts consumed by `BeamAgent.Verifier`, e.g.
      `:required_tools`, or `:module` to swap in a custom
      `BeamAgent.Verifier.Behaviour` implementation.
  """
  @spec run(String.t(), keyword()) :: {:ok, Run.t()} | {:error, Run.t()}
  def run(goal, opts) do
    metadata = %{run_id: make_ref(), telemetry_span_context: make_ref()}
    started_at = System.monotonic_time()

    Telemetry.execute(
      [:run, :start],
      %{system_time: System.system_time(), monotonic_time: started_at},
      metadata
    )

    try do
      execute_run(goal, opts, metadata.run_id)
    catch
      kind, reason ->
        Telemetry.execute(
          [:run, :exception],
          terminal_measurements(started_at),
          Map.merge(metadata, %{kind: kind, error_type: :exception})
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    else
      {result, measurements, details} ->
        Telemetry.execute(
          [:run, :stop],
          Map.merge(measurements, terminal_measurements(started_at)),
          Map.merge(metadata, details)
        )

        result
    end
  end

  defp execute_run(goal, opts, run_id) do
    timeout =
      opts
      |> Keyword.get(:guardrails, [])
      |> Keyword.get(:max_execution_time_ms, 30_000)

    opts =
      opts
      |> Keyword.put(:goal, goal)
      |> Keyword.put(:run_id, run_id)

    with {:ok, pid} <-
           RunSupervisor.start_run(opts) do
      monitor_ref = Process.monitor(pid)
      Runner.run(pid, self())

      result =
        await_run(
          pid,
          monitor_ref,
          goal,
          timeout + @timeout_grace_ms
        )

      {measurements, details} = run_details(result)
      {result, measurements, details}
    else
      {:error, reason} ->
        result = IO.puts("Could not start run due to this error: #{inspect(reason)}")

        {result, %{},
         %{
           outcome: :error,
           execution_status: :unknown,
           verification_status: :unknown,
           error_type: :startup_failed
         }}
    end
  end

  defp terminal_measurements(started_at) do
    now = System.monotonic_time()
    %{duration: now - started_at, monotonic_time: now}
  end

  defp run_details({outcome, %Run{} = run}) when outcome in [:ok, :error] do
    measurements = %{iterations: run.iterations, tool_calls: run.tool_calls}

    metadata = %{
      outcome: outcome,
      execution_status: run.execution_status,
      verification_status: run.verification_status
    }

    case outcome do
      :ok -> {measurements, metadata}
      :error -> {measurements, Map.put(metadata, :error_type, run_error_type(run))}
    end
  end

  # Preserve even an unexpected result message; observation must not change it.
  defp run_details(_result) do
    {%{},
     %{
       outcome: :error,
       execution_status: :unknown,
       verification_status: :unknown,
       error_type: :unexpected_result
     }}
  end

  defp run_error_type(%Run{verification_status: :failed}), do: :verification_failed

  defp run_error_type(%Run{error: reason})
       when reason in [:max_iterations_reached, :max_tool_calls_reached, :unknown_tool],
       do: reason

  defp run_error_type(%Run{error: {type, _details}})
       when type in [
              :runner_crashed,
              :execution_timeout,
              :max_execution_time_reached,
              :max_context_messages_exceeded,
              :context_limit_too_small
            ],
       do: type

  defp run_error_type(_run), do: :execution_failed

  defp await_run(
         pid,
         monitor_ref,
         goal,
         timeout
       ) do
    receive do
      {:agent_run_finished, ^pid, result} ->
        Process.demonitor(
          monitor_ref,
          [:flush]
        )

        result

      {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
        crash_result(
          goal,
          reason
        )
    after
      timeout ->
        timeout_result(
          pid,
          monitor_ref,
          goal,
          timeout
        )
    end
  end

  defp timeout_result(
         pid,
         monitor_ref,
         goal,
         timeout
       ) do
    terminate_runner(pid)

    receive do
      {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
        :ok
    after
      100 ->
        Process.demonitor(
          monitor_ref,
          [:flush]
        )
    end

    {:error,
     Run.timeout(
       goal,
       timeout
     )}
  end

  defp terminate_runner(pid) do
    case DynamicSupervisor.terminate_child(
           RunSupervisor,
           pid
         ) do
      :ok ->
        :ok

      {:error, :not_found} ->
        :ok
    end
  end

  defp crash_result(goal, reason) do
    {:error,
     Run.crash(
       goal,
       reason
     )}
  end
end
