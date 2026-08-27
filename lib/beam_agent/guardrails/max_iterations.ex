defmodule BeamAgent.Guardrails.MaxIterations do
  @moduledoc """
  Guardrail for enforcing maximum iteration limits.
  """

  @doc """
  Checks if iteration count exceeds `opts[:max_iterations]` (default 5).
  """
  @spec check(BeamAgent.State.t(), keyword()) :: :ok | {:error, :max_iterations_reached}
  def check(state, opts) do
    maximum =
      Keyword.get(
        opts,
        :max_iterations,
        5
      )

    if state.iteration >= maximum do
      {:error, :max_iterations_reached}
    else
      :ok
    end
  end
end
