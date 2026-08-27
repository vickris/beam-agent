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
  """

  use GenServer

  alias BeamAgent.Context
  alias BeamAgent.Guardrails
  alias BeamAgent.State
  alias BeamAgent.Tools

  @type tools :: Tools.Registry.tools()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
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
        verification
      )

    send(caller, {:agent_run_finished, self(), result})

    {:stop, :normal, state}
  end

  defp step(state, llm, tools, guardrails) do
    case prepare_context(state, guardrails) do
      {:ok, state} ->
        run_checks(state, llm, tools, guardrails)

      {:error, reason, failed_state} ->
        {:error, reason, failed_state}
    end
  end

  defp run_checks(state, llm, tools, guardrails) do
    with :ok <- Guardrails.check_before_step(state, guardrails),
         {:ok, _} <- prepare_context(state, guardrails),
         :ok <- Guardrails.check_context(state, guardrails) do
      state
      |> State.increment_iteration()
      |> State.trace(:model_call, %{
        message_count: state.context |> Context.messages() |> length(),
        elapsed_ms: State.elapsed_ms(state)
      })
      |> call_llm(llm, tools, guardrails)
    else
      {:error, reason, %State{} = failed_state} ->
        {:error, reason, failed_state}

      {:error, reason} ->
        failed_state = State.fail(state, reason)
        {:error, reason, failed_state}
    end
  end

  defp call_llm(state, {module, opts} = llm, tools, guardrails) do
    case module.chat(Context.messages(state.context), opts) do
      {:reply, reply} ->
        state =
          state
          |> State.add_assistant_message(reply)
          |> State.trace(:model_finished, %{answer: reply})
          |> State.finish(reply)

        {:ok, reply, state}

      {:tool_call, tool, args} ->
        state = State.trace(state, :tool_requested, %{tool: tool, arguments: args})
        run_tool(state, tool, args, llm, tools, guardrails)
    end
  end

  defp prepare_context(state, guardrails) do
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
        compressed_state =
          state
          |> State.put_context(context)
          |> State.trace(
            :context_compressed,
            metadata
          )

        {:ok, compressed_state}

      {:error, reason} ->
        failed_state = State.fail(state, reason)
        {:error, reason, failed_state}
    end
  end

  defp run_tool(state, tool, args, llm, tools, guardrails) do
    with :ok <- Guardrails.check_before_tool(state, guardrails) do
      execute_tool(state, tool, args, llm, tools, guardrails)
    else
      {:error, reason} ->
        failed_state = State.fail(state, reason)
        {:error, reason, failed_state}
    end
  end

  defp execute_tool(state, tool, args, llm, tools, guardrails) do
    state =
      state
      |> State.increment_tool_calls()

    state =
      State.trace(
        state,
        :tool_started,
        %{
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
            tool: tool,
            result: result,
            tool_call_number: state.tool_calls
          })
          |> State.add_tool_result(result)

        step(state, llm, tools, guardrails)

      {:error, reason} ->
        failed_state =
          state
          |> State.trace(:tool_failed, %{
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
         verification
       ) do
    case step(
           execution,
           llm,
           tools,
           guardrails
         ) do
      {:ok, _result, final_state} ->
        final_state
        |> build_verified_run(verification)
        |> public_result()

      {:error, reason, final_state} ->
        final_state
        |> BeamAgent.Run.Builder.execution_failed(reason)
        |> public_result()
    end
  end

  defp build_verified_run(
         final_state,
         verification
       ) do
    candidate =
      BeamAgent.Run.Builder.success(final_state)

    case BeamAgent.Verifier.verify(
           candidate,
           verification
         ) do
      :ok ->
        candidate

      {:error, reason} ->
        BeamAgent.Run.Builder.verification_failed(
          final_state,
          reason
        )
    end
  end

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
