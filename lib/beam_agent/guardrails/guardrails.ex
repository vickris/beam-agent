defmodule BeamAgent.Guardrails do
  alias BeamAgent.Guardrails.{
    MaxContextMessages,
    MaxIterations,
    MaxExecutionTime,
    MaxToolCalls
  }

  def check_before_step(state, opts) do
    with :ok <- MaxExecutionTime.check(state, opts),
         :ok <- MaxIterations.check(state, opts) do
      :ok
    else
      error -> error
    end
  end

  def check_before_tool(state, opts) do
    with :ok <- MaxExecutionTime.check(state, opts),
         :ok <- MaxIterations.check(state, opts),
         :ok <- MaxToolCalls.check(state, opts) do
      :ok
    else
      error -> error
    end
  end

  def check_iterations(state, opts) do
    MaxIterations.check(state, opts)
  end

  def check_context(state, opts) do
    MaxContextMessages.check(state, opts)
  end
end
