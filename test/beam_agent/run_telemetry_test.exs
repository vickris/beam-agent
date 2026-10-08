defmodule BeamAgent.RunTelemetryTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  alias BeamAgent.API

  @secret "sensitive goal, arguments, result, response, and exception"
  @events for phase <- [:start, :stop, :exception], do: [:beam_agent, :run, phase]

  defmodule Model do
    @behaviour BeamAgent.LLM.Client

    @impl true
    def chat(messages, opts) do
      case Keyword.get(opts, :mode, :reply) do
        :reply ->
          {:reply, opts[:secret]}

        :tool ->
          if List.last(messages).role == :tool do
            {:reply, opts[:secret]}
          else
            {:tool_call, %{id: opts[:secret], name: :echo, arguments: %{text: opts[:secret]}}}
          end

        :crash ->
          raise opts[:secret]

        :block ->
          send(opts[:owner], {:blocked, self()})

          receive do
            :release -> {:reply, opts[:secret]}
          end
      end
    end
  end

  defmodule RejectingTool do
    @behaviour BeamAgent.Tools.Behaviour
    @impl true
    def name, do: :echo
    @impl true
    def description, do: "Test returned errors"
    @impl true
    def execute(args), do: {:error, args}
  end

  defmodule BlockingVerifier do
    @behaviour BeamAgent.Verifier.Behaviour

    @impl true
    def verify(_run, opts) do
      send(opts[:owner], {:verifying, self()})

      receive do
        :finish_verification -> :ok
      end
    end
  end

  setup do
    tag = make_ref()
    id = {__MODULE__, tag}
    on_exit(fn -> :telemetry.detach(id) end)
    :ok = :telemetry.attach_many(id, @events, &__MODULE__.handle_event/4, {self(), tag})
    %{tag: tag}
  end

  test "successful runs emit a content-free API span with counters", %{tag: tag} do
    assert {:ok, run} =
             API.run(@secret,
               llm: {Model, mode: :tool, secret: @secret},
               tools: %{echo: BeamAgent.Tools.Echo}
             )

    assert run.answer == @secret

    {measurements, _metadata} =
      assert_span(tag, :stop, %{
        outcome: :ok,
        execution_status: :finished,
        verification_status: :passed
      })

    assert measurements.iterations == run.iterations
    assert measurements.tool_calls == run.tool_calls
    refute Map.has_key?(run, :run_id)
  end

  test "verification failure is a stop, retaining the original result", %{tag: tag} do
    assert {:error, run} =
             API.run(@secret,
               llm: {Model, secret: @secret},
               verification: [required_tools: [:echo]]
             )

    assert run.answer == @secret
    assert run.verification_error == {:missing_required_tools, [:echo]}

    assert_span(tag, :stop, %{
      outcome: :error,
      execution_status: :finished,
      verification_status: :failed,
      error_type: :verification_failed
    })
  end

  test "the run span remains open until verification returns", %{tag: tag} do
    owner = self()

    task =
      Task.async(fn ->
        API.run(@secret,
          llm: {Model, secret: @secret},
          verification: [module: BlockingVerifier, owner: owner]
        )
      end)

    assert_receive {:verifying, runner}
    on_exit(fn -> DynamicSupervisor.terminate_child(BeamAgent.RunSupervisor, runner) end)
    caller = task.pid
    refute_received {^tag, ^caller, [:beam_agent, :run, :stop], _, _}
    refute_received {^tag, ^caller, [:beam_agent, :run, :exception], _, _}
    send(runner, :finish_verification)
    assert {:ok, _run} = Task.await(task)

    assert_span(
      tag,
      :stop,
      %{
        outcome: :ok,
        execution_status: :finished,
        verification_status: :passed
      },
      caller
    )
  end

  test "a handled runner crash is a stop without raw exceptions", %{tag: tag} do
    capture_log(fn ->
      assert {:error, run} = API.run(@secret, llm: {Model, mode: :crash, secret: @secret})
      assert {:runner_crashed, _reason} = run.error
    end)

    {measurements, _metadata} = assert_failed_run(tag, :runner_crashed)
    refute Map.has_key?(measurements, :iterations)
    refute Map.has_key?(measurements, :tool_calls)
  end

  test "hard timeout closes the API span after runner termination", %{tag: tag} do
    owner = self()

    task =
      Task.async(fn ->
        API.run(@secret,
          llm: {Model, mode: :block, owner: owner, secret: @secret},
          guardrails: [max_execution_time_ms: 10]
        )
      end)

    assert_receive {:blocked, runner}
    monitor = Process.monitor(runner)
    on_exit(fn -> DynamicSupervisor.terminate_child(BeamAgent.RunSupervisor, runner) end)

    assert {:error, run} = Task.await(task, 5_000)
    assert run.error == {:execution_timeout, 1_010}
    assert_receive {:DOWN, ^monitor, :process, ^runner, _reason}

    {measurements, _metadata} = assert_failed_run(tag, :execution_timeout, task.pid)
    assert System.convert_time_unit(measurements.duration, :native, :millisecond) >= 1_010
    refute Map.has_key?(measurements, :iterations)
  end

  test "startup failure preserves the existing :ok return but reports failure", %{tag: tag} do
    capture_log(fn ->
      output = capture_io(fn -> assert :ok = API.run(@secret, []) end)
      assert output =~ "Could not start run"
    end)

    assert_span(tag, :stop, %{
      outcome: :error,
      execution_status: :unknown,
      verification_status: :unknown,
      error_type: :startup_failed
    })
  end

  test "handled guardrails, unknown tools, and arbitrary tool errors are classified", %{tag: tag} do
    cases = [
      {[guardrails: [max_iterations: 0]], :max_iterations_reached},
      {[guardrails: [max_tool_calls: 0]], :max_tool_calls_reached},
      {[guardrails: [max_execution_time_ms: 0]], :max_execution_time_reached},
      {[guardrails: [max_context_messages: 0]], :context_limit_too_small},
      {[], :unknown_tool},
      {[tools: %{echo: RejectingTool}], :execution_failed}
    ]

    for {options, error_type} <- cases do
      opts = Keyword.put(options, :llm, {Model, mode: :tool, secret: @secret})
      assert {:error, _run} = API.run(@secret, opts)
      assert_failed_run(tag, error_type)
    end
  end

  test "escaping exceptions are re-raised and emit exception, not stop", %{tag: tag} do
    assert_raise FunctionClauseError, fn -> API.run(@secret, %{prompt: @secret}) end
    assert_span(tag, :exception, %{kind: :error, error_type: :exception})
  end

  test "an escaping supervisor exit is preserved", %{tag: tag} do
    supervisor = Process.whereis(BeamAgent.RunSupervisor)
    Process.unregister(BeamAgent.RunSupervisor)

    try do
      reason = catch_exit(API.run(@secret, llm: {Model, secret: @secret}))
      assert {:noproc, {GenServer, :call, _args}} = reason
      assert_span(tag, :exception, %{kind: :exit, error_type: :exception})
    after
      Process.register(supervisor, BeamAgent.RunSupervisor)
    end
  end

  test "a throw from startup error formatting escapes unchanged", %{tag: tag} do
    original = Inspect.Opts.default_inspect_fun()
    owner = self()

    # Exercise the existing inspect/1 boundary without a production test hook.
    # Other processes retain the original inspector; restore before assertions.
    Inspect.Opts.default_inspect_fun(fn value, opts ->
      if self() == owner, do: throw({:private_reason, @secret}), else: original.(value, opts)
    end)

    escaped =
      try do
        API.run(@secret, [])
      catch
        kind, reason -> {kind, reason, __STACKTRACE__}
      after
        Inspect.Opts.default_inspect_fun(original)
      end

    assert {:throw, {:private_reason, @secret}, stacktrace} = escaped

    assert Enum.any?(stacktrace, fn {module, function, _, _} ->
             module == API and function == :execute_run
           end)

    assert_span(tag, :exception, %{kind: :throw, error_type: :exception})
  end

  test "concurrent runs have independent IDs and span contexts", %{tag: tag} do
    tasks =
      for _ <- 1..3, do: Task.async(fn -> API.run(@secret, llm: {Model, secret: @secret}) end)

    metadata =
      Enum.map(tasks, fn task ->
        assert {:ok, _run} = Task.await(task)

        {_measurements, metadata} =
          assert_span(
            tag,
            :stop,
            %{
              outcome: :ok,
              execution_status: :finished,
              verification_status: :passed
            },
            task.pid
          )

        metadata
      end)

    assert length(Enum.uniq_by(metadata, & &1.run_id)) == 3
    assert length(Enum.uniq_by(metadata, & &1.telemetry_span_context)) == 3
  end

  def handle_event(event, measurements, metadata, {owner, tag}) do
    send(owner, {tag, self(), event, measurements, metadata})
  end

  defp assert_failed_run(tag, error_type, caller \\ self()) do
    assert_span(
      tag,
      :stop,
      %{
        outcome: :error,
        execution_status: :failed,
        verification_status: :not_run,
        error_type: error_type
      },
      caller
    )
  end

  defp assert_span(tag, phase, expected, caller \\ self()) do
    assert_receive {^tag, ^caller, [:beam_agent, :run, :start], start, start_metadata}
    assert Map.keys(start) |> Enum.sort() == [:monotonic_time, :system_time]
    assert is_integer(start.system_time)
    assert is_reference(start_metadata.run_id)
    assert is_reference(start_metadata.telemetry_span_context)
    refute start_metadata.run_id == start_metadata.telemetry_span_context
    assert map_size(start_metadata) == 2

    assert_receive {^tag, ^caller, [:beam_agent, :run, ^phase], terminal, metadata}
    assert metadata == Map.merge(start_metadata, expected)
    assert terminal.duration >= 0
    assert terminal.duration == terminal.monotonic_time - start.monotonic_time

    assert Enum.all?(terminal, fn {key, value} ->
             key in [:duration, :monotonic_time, :iterations, :tool_calls] and is_integer(value)
           end)

    refute_received {^tag, ^caller, [:beam_agent, :run, _], _, _}
    {terminal, metadata}
  end
end
