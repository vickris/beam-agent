defmodule BeamAgent.Run.Builder do
  @moduledoc """
  Converts internal execution state into a structured `BeamAgent.Run` representation, capturing the goal, answer, status, trace, and timestamps of the agent's execution.
  """

  alias BeamAgent.Run
  alias BeamAgent.State

  def success(%State{} = state) do
    build(state, verification_status: :passed)
  end

  def verification_failed(%State{} = state, reason) do
    build(state, verification_status: :failed, verification_error: reason)
  end

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
