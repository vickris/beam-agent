defmodule BeamAgentTest do
  use ExUnit.Case
  doctest BeamAgent

  test "greets the world" do
    assert BeamAgent.hello() == :world
  end
end
