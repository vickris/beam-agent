defmodule BeamAgent.Runner do
  @moduledoc """
  Executes one isolated agent run.

  Each run is its own `GenServer`, started anonymously (no name
  registration) by `BeamAgent.RunSupervisor`, so many runs can be in flight
  concurrently and one crashing has no effect on the others — the crash is
  contained to this process and surfaces to the caller of
  `BeamAgent.API.run/2` as a `{:runner_crashed, reason}` error, not a
  propagating exit.

  `start_link/1` accepts:

    * `:goal` (required) — the natural-language goal for the run.
    * `:llm` (required) — `{module, opts}`, where `module` implements
      `BeamAgent.LLM.Client`.
    * `:tools` — `%{atom() => module}` of tools available to this run, each
      module implementing `BeamAgent.Tools.Behaviour`. Defaults to `%{}`.
    * `:guardrails` — options consumed by `BeamAgent.Guardrails`.
    * `:verification` — options consumed by `BeamAgent.Verifier`.

  Call `run/2` to kick off execution; the result arrives as
  `{:agent_run_finished, pid, result}` sent to the given caller, after which
  this process stops normally.

  ## Verification, context, and guardrail telemetry

  Verification emits `[:beam_agent, :verification, :start | :stop | :exception]`
  around the configured verifier invocation only. Events carry `:run_id` and
  a fresh `:telemetry_span_context`. Starts measure system and monotonic time;
  terminals measure monotonic time and duration, all in native units. Stops
  classify outcome and verification status; errors use `:verification_failed`
  (or `:unexpected_result` for malformed returns). Exceptions include only
  `:kind` and `error_type: :exception`, and are re-raised unchanged.

  Context emits `[:beam_agent, :context, :compressed]` only for actual
  compression, with `:before_count`, `:after_count`, `:compressed_messages`, and
  `:summary_chars` measurements. `:compression_failed` reports
  `:configured_max_messages` and `:minimum_messages`, with
  `error_type: :context_limit_too_small`. If that limit blocks compression,
  the unsatisfied context guardrail also emits one rejection, with the current
  rendered message count as `:observed` and the configured cap as `:limit`.

  Guardrail rejection emits `[:beam_agent, :guardrail, :rejected]` with numeric
  `:observed` and `:limit` measurements. Metadata identifies `:guardrail`
  (`:max_iterations`, `:max_tool_calls`, `:max_context_messages`, or
  `:max_execution_time`), `:phase` (`:before_step`, `:before_tool`, or `:context`),
  and `:unit` (`:count` or `:millisecond`). Successful checks stay silent.

  All point events include system/monotonic timestamps, `count: 1`, and metadata
  containing `:run_id` and the current `:iteration` (zero before the first model
  call). No execution content or raw failure reasons are emitted. Standalone
  context, verifier, and guardrail calls remain uninstrumented.
  """

  use GenServer

  alias BeamAgent.Context
  alias BeamAgent.Guardrails
  alias BeamAgent.State
  alias BeamAgent.Tools
  alias BeamAgent.Telemetry
  alias BeamAgent.Guardrails.Telemetry, as: GuardrailTelemetry

  @type tools :: Tools.Registry.tools()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    # Direct starts also get correlation identity before the process is created.
    opts = Keyword.put_new_lazy(opts, :run_id, &make_ref/0)

    GenServer.start_link(
      __MODULE__,
      opts
    )
  end

  @impl true
  def init(opts) do
    goal = Keyword.fetch!(opts, :goal)
    llm = Keyword.fetch!(opts, :llm)

    state = %{
      run_id: Keyword.fetch!(opts, :run_id),
      llm: llm,
      tools: Keyword.get(opts, :tools, %{}),
      verification: Keyword.get(opts, :verification, []),
      guardrails: Keyword.get(opts, :guardrails, []),
      execution: State.new(goal)
    }

    {:ok, state}
  end

  @doc """
  Starts execution of `pid`'s run; the result is sent to `caller` as
  `{:agent_run_finished, pid, result}`.
  """
  @spec run(pid(), pid()) :: :ok
  def run(pid, caller) do
    GenServer.cast(
      pid,
      {:run, caller}
    )
  end

  @impl true
  def handle_cast(
        {:run, caller},
        %{
          execution: execution,
          run_id: run_id,
          llm: llm,
          tools: tools,
          guardrails: guardrails,
          verification: verification
        } = state
      ) do
    result =
      execute(
        execution,
        llm,
        tools,
        guardrails,
        verification,
        run_id
      )

    send(caller, {:agent_run_finished, self(), result})

    {:stop, :normal, state}
  end

  defp step(state, llm, tools, guardrails, run_id) do
    case prepare_context(state, guardrails, run_id) do
      {:ok, state} ->
        run_checks(state, llm, tools, guardrails, run_id)

      {:error, reason, failed_state} ->
        {:error, reason, failed_state}
    end
  end

  defp run_checks(state, llm, tools, guardrails, run_id) do
    with :ok <-
           GuardrailTelemetry.observe(
             Guardrails.check_before_step(state, guardrails),
             state,
             guardrails,
             :before_step,
             run_id
           ),
         {:ok, _} <- prepare_context(state, guardrails, run_id),
         :ok <-
           GuardrailTelemetry.observe(
             Guardrails.check_context(state, guardrails),
             state,
             guardrails,
             :context,
             run_id
           ) do
      state
      |> State.increment_iteration()
      |> State.trace(:model_call, %{
        message_count: state.context |> Context.messages() |> length(),
        elapsed_ms: State.elapsed_ms(state)
      })
      |> call_llm(llm, tools, guardrails, run_id)
    else
      {:error, reason, %State{} = failed_state} ->
        {:error, reason, failed_state}

      {:error, reason} ->
        failed_state = State.fail(state, reason)
        {:error, reason, failed_state}
    end
  end

  defp call_llm(state, {module, opts} = llm, tools, guardrails, run_id) do
    case module.chat(Context.messages(state.context), opts) do
      {:reply, reply} ->
        state =
          state
          |> State.add_assistant_message(reply)
          |> State.trace(:model_finished, %{answer: reply})
          |> State.finish(reply)

        {:ok, reply, state}

      {:tool_call, tool_call} ->
        state =
          state
          |> State.add_tool_call(tool_call)
          |> State.trace(:tool_requested, %{
            tool_call_id: tool_call.id,
            tool: tool_call.name,
            arguments: tool_call.arguments
          })

        run_tool(state, tool_call, llm, tools, guardrails, run_id)
    end
  end

  defp prepare_context(state, guardrails, run_id) do
    max_messages =
      Keyword.get(
        guardrails,
        :max_context_messages,
        8
      )

    summary_char_limit =
      Keyword.get(
        guardrails,
        :summary_char_limit,
        1_000
      )

    options = [
      max_messages: max_messages,
      summary_char_limit: summary_char_limit
    ]

    case Context.compress(
           state.context,
           options
         ) do
      {:ok, _context, %{compressed?: false}} ->
        {:ok, state}

      {:ok, context, metadata} ->
        Telemetry.point(
          [:context, :compressed],
          Map.take(metadata, [:before_count, :after_count, :compressed_messages, :summary_chars]),
          %{run_id: run_id, iteration: state.iteration}
        )

        compressed_state =
          state
          |> State.put_context(context)
          |> State.trace(
            :context_compressed,
            metadata
          )

        {:ok, compressed_state}

      {:error, reason} ->
        compression_failed(reason, state, guardrails, run_id)
        failed_state = State.fail(state, reason)
        {:error, reason, failed_state}
    end
  end

  defp compression_failed(
         {:context_limit_too_small, %{configured: configured, minimum: minimum}},
         state,
         guardrails,
         run_id
       ) do
    Telemetry.point(
      [:context, :compression_failed],
      %{configured_max_messages: configured, minimum_messages: minimum},
      %{run_id: run_id, iteration: state.iteration, error_type: :context_limit_too_small}
    )

    GuardrailTelemetry.observe(
      Guardrails.check_context(state, guardrails),
      state,
      guardrails,
      :context,
      run_id
    )
  end

  defp compression_failed(_reason, _state, _guardrails, _run_id), do: :ok

  defp run_tool(state, tool_call, llm, tools, guardrails, run_id) do
    with :ok <-
           GuardrailTelemetry.observe(
             Guardrails.check_before_tool(state, guardrails),
             state,
             guardrails,
             :before_tool,
             run_id
           ) do
      execute_tool(state, tool_call, llm, tools, guardrails, run_id)
    else
      {:error, reason} ->
        failed_state = State.fail(state, reason)
        {:error, reason, failed_state}
    end
  end

  defp execute_tool(
         state,
         %{id: tool_call_id, name: tool, arguments: args},
         llm,
         tools,
         guardrails,
         run_id
       ) do
    state =
      state
      |> State.increment_tool_calls()

    state =
      State.trace(
        state,
        :tool_started,
        %{
          tool_call_id: tool_call_id,
          tool: tool,
          arguments: args,
          tool_call_number: state.tool_calls + 1
        }
      )

    case Tools.Registry.call(tools, tool, args) do
      {:ok, result} ->
        state =
          state
          |> State.trace(:tool_completed, %{
            tool_call_id: tool_call_id,
            tool: tool,
            result: result,
            tool_call_number: state.tool_calls
          })
          |> State.add_tool_result(tool_call_id, result)

        step(state, llm, tools, guardrails, run_id)

      {:error, reason} ->
        failed_state =
          state
          |> State.trace(:tool_failed, %{
            tool_call_id: tool_call_id,
            tool: tool,
            reason: reason,
            tool_call_number: state.tool_calls
          })
          |> State.fail(reason)

        {:error, reason, failed_state}
    end
  end

  defp public_result(
         %BeamAgent.Run{
           execution_status: :finished,
           verification_status: :passed
         } = run
       ) do
    {:ok, run}
  end

  defp public_result(%BeamAgent.Run{} = run) do
    {:error, run}
  end

  defp execute(
         execution,
         llm,
         tools,
         guardrails,
         verification,
         run_id
       ) do
    case step(
           execution,
           llm,
           tools,
           guardrails,
           run_id
         ) do
      {:ok, _result, final_state} ->
        final_state
        |> build_verified_run(verification, run_id)
        |> public_result()

      {:error, reason, final_state} ->
        final_state
        |> BeamAgent.Run.Builder.execution_failed(reason)
        |> public_result()
    end
  end

  defp build_verified_run(
         final_state,
         verification,
         run_id
       ) do
    candidate =
      BeamAgent.Run.Builder.success(final_state)

    case verify(candidate, verification, run_id) do
      :ok ->
        candidate

      {:error, reason} ->
        BeamAgent.Run.Builder.verification_failed(
          final_state,
          reason
        )
    end
  end

  defp verify(candidate, opts, run_id) do
    module = Keyword.get(opts, :module, BeamAgent.Verifier.Default)
    metadata = %{run_id: run_id, telemetry_span_context: make_ref()}
    started_at = System.monotonic_time()

    Telemetry.execute(
      [:verification, :start],
      %{system_time: System.system_time(), monotonic_time: started_at},
      metadata
    )

    try do
      module.verify(candidate, opts)
    catch
      kind, reason ->
        Telemetry.execute(
          [:verification, :exception],
          verification_timing(started_at),
          Map.merge(metadata, %{kind: kind, error_type: :exception})
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    else
      result ->
        Telemetry.execute(
          [:verification, :stop],
          verification_timing(started_at),
          Map.merge(metadata, verification_outcome(result))
        )

        result
    end
  end

  defp verification_timing(started_at) do
    now = System.monotonic_time()
    %{monotonic_time: now, duration: now - started_at}
  end

  defp verification_outcome(:ok), do: %{outcome: :ok, verification_status: :passed}

  defp verification_outcome({:error, _reason}),
    do: %{outcome: :error, verification_status: :failed, error_type: :verification_failed}

  defp verification_outcome(_result),
    do: %{outcome: :error, verification_status: :unknown, error_type: :unexpected_result}

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: make_ref(),
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end
end
