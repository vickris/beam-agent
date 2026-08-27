defmodule BeamAgent.State do
  @moduledoc """
  Holds the runtime state for a single agent execution.

  Internal to a run's lifecycle inside `BeamAgent.Runner` — not the public
  result type (that's `BeamAgent.Run`, built from this via
  `BeamAgent.Run.Builder` once the run finishes or fails).
  """

  @type status :: :running | :finished | :failed

  @type t :: %__MODULE__{
          goal: String.t(),
          status: status(),
          iteration: non_neg_integer(),
          tool_calls: non_neg_integer(),
          context: BeamAgent.Context.t(),
          trace: [BeamAgent.Trace.Step.t()],
          result: term() | nil,
          started_at: DateTime.t(),
          started_at_monotonic: integer()
        }

  defstruct [
    :goal,
    :status,
    :iteration,
    :tool_calls,
    :context,
    :trace,
    :result,
    :started_at,
    :started_at_monotonic
  ]

  @doc "Starts a fresh, `:running` state for `goal`."
  @spec new(String.t()) :: t()
  def new(goal) do
    %__MODULE__{
      goal: goal,
      status: :running,
      iteration: 0,
      tool_calls: 0,
      context: BeamAgent.Context.new(goal),
      trace: [],
      started_at: DateTime.utc_now(),
      started_at_monotonic: System.monotonic_time(:millisecond)
    }
  end

  @doc "Appends one trace step of `type` with `payload`, tagged with the current iteration."
  @spec trace(t(), atom(), map()) :: t()
  def trace(state, type, payload) do
    %{
      state
      | trace:
          BeamAgent.Trace.record(
            state.trace,
            state.iteration,
            type,
            payload
          )
    }
  end

  @doc "Appends a tool result to the run's context."
  @spec add_tool_result(t(), term()) :: t()
  def add_tool_result(state, result) do
    update_context(state, &BeamAgent.Context.add_tool_result(&1, result))
  end

  @doc "Appends an assistant reply to the run's context."
  @spec add_assistant_message(t(), String.t()) :: t()
  def add_assistant_message(state, reply) do
    update_context(state, &BeamAgent.Context.add_assistant_message(&1, reply))
  end

  @doc "Increments the loop iteration counter by one."
  @spec increment_iteration(t()) :: t()
  def increment_iteration(state) do
    %{state | iteration: state.iteration + 1}
  end

  @doc "Increments the tool-call counter by one."
  @spec increment_tool_calls(t()) :: t()
  def increment_tool_calls(state) do
    %{state | tool_calls: state.tool_calls + 1}
  end

  @doc "Milliseconds elapsed (monotonic clock) since the state was created."
  @spec elapsed_ms(t()) :: non_neg_integer()
  def elapsed_ms(state) do
    System.monotonic_time(:millisecond) - state.started_at_monotonic
  end

  @doc "Marks the state `:finished` with the given `result` (the model's final reply)."
  @spec finish(t(), String.t()) :: t()
  def finish(state, result) do
    state
    |> trace(:finished, %{result: result})
    |> Map.put(:status, :finished)
    |> Map.put(:result, result)
  end

  @doc "Marks the state `:failed` with the given `reason`."
  @spec fail(t(), term()) :: t()
  def fail(state, reason) do
    state
    |> trace(:failed, %{reason: reason})
    |> Map.put(:status, :failed)
    |> Map.put(:result, reason)
  end

  defp update_context(state, fun) do
    %{state | context: fun.(state.context)}
  end

  @doc "Replaces the run's context (used after compression)."
  @spec put_context(t(), BeamAgent.Context.t()) :: t()
  def put_context(state, %BeamAgent.Context{} = context) do
    %{state | context: context}
  end
end
