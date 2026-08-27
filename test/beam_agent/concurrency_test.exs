defmodule BeamAgent.ConcurrencyTest do
  use ExUnit.Case, async: true

  alias BeamAgent.Tools.{Crash, Echo}

  test "runs many goals concurrently without cross-run interference" do
    goals = for n <- 1..10, do: "goal #{n}"

    results =
      goals
      |> Enum.map(fn goal ->
        Task.async(fn ->
          BeamAgent.API.run(
            goal,
            llm: {BeamAgent.LLM.Mock, mode: :normal},
            tools: %{echo: Echo},
            verification: [required_tools: [:echo]]
          )
        end)
      end)
      |> Task.await_many(5_000)

    assert length(results) == length(goals)

    Enum.zip(goals, results)
    |> Enum.each(fn {goal, result} ->
      assert {:ok, run} = result
      # Each run's own goal made it through its own isolated process
      # untouched by any of the other concurrently-running goals.
      assert run.goal == goal
      assert run.answer == "Done!"
      assert run.tool_calls == 1
    end)
  end

  test "a crashing run does not affect concurrently running goals" do
    crashing =
      Task.async(fn ->
        BeamAgent.API.run(
          "Crash",
          llm: {BeamAgent.LLM.Mock, mode: :crash_tool},
          tools: %{crash: Crash},
          guardrails: [max_execution_time_ms: 1_000]
        )
      end)

    healthy =
      for n <- 1..5 do
        Task.async(fn ->
          BeamAgent.API.run(
            "healthy #{n}",
            llm: {BeamAgent.LLM.Mock, mode: :normal},
            tools: %{echo: Echo},
            verification: [required_tools: [:echo]]
          )
        end)
      end

    assert {:error, crashed_run} = Task.await(crashing, 5_000)
    assert {:runner_crashed, _reason} = crashed_run.error

    healthy
    |> Task.await_many(5_000)
    |> Enum.each(fn result ->
      assert {:ok, run} = result
      assert run.answer == "Done!"
    end)
  end
end
