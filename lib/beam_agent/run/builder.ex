defmodule BeamAgent.Run.Builder do
  @moduledoc """
  Converts internal execution state into a structured `BeamAgent.Run`
  representation, capturing the goal, answer, status, trace, and timestamps
  of the agent's execution.
  """

  alias BeamAgent.Run
  alias BeamAgent.State

  @doc """
  Builds a `Run` with `verification_status: :passed` from a finished
  `state`. Used as the verification candidate before `BeamAgent.Verifier`
  runs against it.
  """
  @spec success(State.t()) :: Run.t()
  def success(%State{} = state) do
    build(state, verification_status: :passed)
  end

  @doc """
  Builds a `Run` with `verification_status: :failed` and the given `reason`
  recorded as `verification_error`.
  """
  @spec verification_failed(State.t(), term()) :: Run.t()
  def verification_failed(%State{} = state, reason) do
    build(state, verification_status: :failed, verification_error: reason)
  end

  @doc """
  Builds a `Run` for a state that failed before ever reaching a reply
  (a guardrail tripped, context couldn't be compressed, an unknown tool was
  called, ...). `verification_status` is `:not_run` since verification never
  gets a chance to run.
  """
  @spec execution_failed(State.t(), term()) :: Run.t()
  def execution_failed(%State{} = state, reason) do
    build(state, execution_status: :failed, verification_status: :not_run, error: reason)
  end

  defp build(%State{} = state, overrides) do
    defaults = [
      execution_status: state.status,
      verification_status: :not_run,
      answer: answer_from_state(state),
      error: error_from_state(state),
      verification_error: nil
    ]

    attributes = Keyword.merge(defaults, overrides)

    %Run{
      goal: state.goal,
      execution_status: Keyword.get(attributes, :execution_status),
      verification_status: Keyword.get(attributes, :verification_status),
      answer: Keyword.get(attributes, :answer),
      error: Keyword.get(attributes, :error),
      iterations: state.iteration,
      tool_calls: state.tool_calls,
      started_at: state.started_at,
      finished_at: DateTime.utc_now(),
      duration_ms: State.elapsed_ms(state),
      trace: state.trace,
      verification_error: Keyword.get(overrides, :verification_error)
    }
  end

  defp answer_from_state(%State{status: :finished, result: result}), do: result
  defp answer_from_state(_state), do: nil

  defp error_from_state(%State{status: :failed, result: result}), do: result
  defp error_from_state(_state), do: nil
end
