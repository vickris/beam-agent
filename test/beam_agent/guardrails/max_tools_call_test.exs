defmodule BeamAgent.Guardrails.MaxToolsCallTest do
  use ExUnit.Case, async: true

  alias BeamAgent.Guardrails.MaxToolCalls
  alias BeamAgent.State

  test "allows tool calls within the limit" do
    state =
      "goal"
      |> State.new()
      |> State.increment_tool_calls()

    assert :ok =
             MaxToolCalls.check(
               state,
               max_tool_calls: 2
             )
  end

  test "rejects execution at the limit" do
    state =
      "goal"
      |> State.new()
      |> State.increment_tool_calls()
      |> State.increment_tool_calls()

    assert {:error, :max_tool_calls_reached} =
             MaxToolCalls.check(
               state,
               max_tool_calls: 2
             )
  end
end
