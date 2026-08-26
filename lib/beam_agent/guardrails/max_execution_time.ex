defmodule BeamAgent.Guardrails.MaxExecutionTime do
  @moduledoc """
  Prevents an agent from executing for longer than the allowed time.
  """

  alias BeamAgent.State

  def check(%State{} = state, opts) do
    max_execution_time_ms = Keyword.get(opts, :max_execution_time_ms, 30_000)

    if State.elapsed_ms(state) >= max_execution_time_ms do
      {:error,
       {:max_execution_time_reached,
        %{
          elapsed_ms: State.elapsed_ms(state),
          maximum_ms: max_execution_time_ms
        }}}
    else
      :ok
    end
  end
end
