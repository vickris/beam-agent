defmodule BeamAgent.RunCorrelationTest do
  use ExUnit.Case, async: false

  alias BeamAgent.Runner
  alias BeamAgent.RunSupervisor

  test "the API creates distinct internal IDs before startup, ignoring supplied IDs" do
    # Observe the existing startup boundary without adding a production hook or
    # emitting runtime telemetry. Only these test-owned callers are traced.
    boundary = {RunSupervisor, :start_run, 1}
    :erlang.trace_pattern(boundary, true, [])
    on_exit(fn -> :erlang.trace_pattern(boundary, false, []) end)
    supplied_id = make_ref()

    tasks =
      for _ <- 1..2 do
        task =
          Task.async(fn ->
            receive do
              :run ->
                BeamAgent.API.run("hello",
                  llm: {BeamAgent.LLM.Mock, []},
                  tools: %{echo: BeamAgent.Tools.Echo},
                  run_id: supplied_id
                )
            end
          end)

        :erlang.trace(task.pid, true, [:call, {:tracer, self()}])
        send(task.pid, :run)
        task
      end

    ids =
      Enum.map(tasks, fn task ->
        caller = task.pid

        assert_receive {:trace, ^caller, :call, {RunSupervisor, :start_run, [opts]}}
        assert is_reference(opts[:run_id])
        refute opts[:run_id] == supplied_id

        assert {:ok, run} = Task.await(task)
        assert run.answer == "Done!"
        refute Map.has_key?(run, :run_id)
        opts[:run_id]
      end)

    assert length(Enum.uniq(ids)) == 2
  end

  test "the supervisor passes the same correlation ID into runner state" do
    run_id = make_ref()

    assert {:ok, runner} =
             RunSupervisor.start_run(
               goal: "hello",
               llm: {BeamAgent.LLM.Mock, []},
               run_id: run_id
             )

    on_exit(fn -> DynamicSupervisor.terminate_child(RunSupervisor, runner) end)
    assert %{run_id: ^run_id} = :sys.get_state(runner)
  end

  test "direct runner starts remain compatible and receive distinct IDs" do
    opts = [goal: "hello", llm: {BeamAgent.LLM.Mock, []}]
    first = start_supervised!({Runner, opts})
    second = start_supervised!({Runner, opts})
    first_id = :sys.get_state(first).run_id
    second_id = :sys.get_state(second).run_id

    assert is_reference(first_id)
    assert is_reference(second_id)
    refute first_id == second_id
  end
end
