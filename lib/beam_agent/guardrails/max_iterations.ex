defmodule BeamAgent.Guardrails.MaxIterations do
  @moduledoc """
  Guardrail for enforcing maximum iteration limits.
  """

  @doc """
  Check if iteration count exceeds maximum allowed iterations.
  """
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
