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
  """

  alias BeamAgent.Run
  alias BeamAgent.RunSupervisor
  alias BeamAgent.Runner

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
    timeout =
      opts
      |> Keyword.get(:guardrails, [])
      |> Keyword.get(:max_execution_time_ms, 30_000)

    opts = Keyword.put(opts, :goal, goal)

    with {:ok, pid} <-
           RunSupervisor.start_run(opts) do
      monitor_ref = Process.monitor(pid)
      Runner.run(pid, self())

      await_run(
        pid,
        monitor_ref,
        goal,
        timeout + @timeout_grace_ms
      )
    else
      {:error, reason} ->
        IO.puts("Could not start run due to this error: #{inspect(reason)}")
    end
  end

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
