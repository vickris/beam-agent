defmodule BeamAgent.Trace do
  @moduledoc """
  Provides tracing functionality for the agent.
  """

  defmodule Step do
    @moduledoc """
    Represents a single trace entry.
    """

    @enforce_keys [:iteration, :type]

    defstruct [
      :iteration,
      :type,
      :timestamp,
      :payload
    ]
  end

  def record(trace, iteration, type, payload) do
    trace ++
      [
        %Step{
          iteration: iteration,
          type: type,
          timestamp: DateTime.utc_now(),
          payload: payload
        }
      ]
  end
end
