defmodule BeamAgent.Guardrails.MaxToolCalls do
  @moduledoc """
  Prevents an agent executing more than the allowed tool calls.
  """

  alias BeamAgent.State

  @doc """
  Checks that the tool-call count is within `opts[:max_tool_calls]` (default 5).
  """
  @spec check(State.t(), keyword()) :: :ok | {:error, :max_tool_calls_reached}
  def check(%State{} = state, opts) do
    max_tool_calls = Keyword.get(opts, :max_tool_calls, 5)

    if state.tool_calls >= max_tool_calls do
      {:error, :max_tool_calls_reached}
    else
      :ok
    end
  end
end
