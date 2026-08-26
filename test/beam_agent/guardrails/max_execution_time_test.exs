defmodule BeamAgent.Guardrails.MaxExecutionTimeTest do
  use ExUnit.Case, async: true

  alias BeamAgent.Guardrails.MaxExecutionTime
  alias BeamAgent.State

  test "rejects a run after its deadline" do
    state = State.new("goal")

    Process.sleep(5)

    assert {
             :error,
             {
               :max_execution_time_reached,
               details
             }
           } =
             MaxExecutionTime.check(
               state,
               max_execution_time_ms: 1
             )

    assert details.elapsed_ms >= 1
  end
end
