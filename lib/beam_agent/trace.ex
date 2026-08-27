defmodule BeamAgent.Trace do
  @moduledoc """
  Provides tracing functionality for the agent.

  Every state transition in `BeamAgent.Runner` is recorded as one `Step`
  into an append-only list — this is the full audit trail exposed as
  `BeamAgent.Run.trace` on both success and failure, not just an internal
  debug log. Typical `:type` values: `:model_call`, `:model_finished`,
  `:tool_requested`, `:tool_started`, `:tool_completed`, `:tool_failed`,
  `:context_compressed`, `:finished`, `:failed`.
  """

  defmodule Step do
    @moduledoc """
    Represents a single trace entry.
    """

    @type t :: %__MODULE__{
            iteration: non_neg_integer(),
            type: atom(),
            timestamp: DateTime.t(),
            payload: map()
          }

    @enforce_keys [:iteration, :type]

    defstruct [
      :iteration,
      :type,
      :timestamp,
      :payload
    ]
  end

  @doc "Appends one `Step` to `trace`, stamped with the current time."
  @spec record([Step.t()], non_neg_integer(), atom(), map()) :: [Step.t()]
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
