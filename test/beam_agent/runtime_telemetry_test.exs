defmodule BeamAgent.RuntimeTelemetryTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias BeamAgent.{API, Context, Guardrails, State}
  alias BeamAgent.Guardrails.Telemetry, as: GuardrailTelemetry

  @secret "private prompt, answer, summary, and verifier reason"
  @events [
    [:beam_agent, :run, :start],
    [:beam_agent, :run, :stop],
    [:beam_agent, :verification, :start],
    [:beam_agent, :verification, :stop],
    [:beam_agent, :verification, :exception],
    [:beam_agent, :context, :compressed],
    [:beam_agent, :context, :compression_failed],
    [:beam_agent, :guardrail, :rejected]
  ]

  defmodule Verifier do
    @behaviour BeamAgent.Verifier.Behaviour
    @impl true
    def verify(run, opts) do
      case opts[:mode] do
        :ok -> :ok
        :reject -> {:error, %{answer: run.answer, trace: run.trace, secret: opts[:secret]}}
        :raise -> raise opts[:secret]
        :throw -> throw({:private, opts[:secret]})
        :exit -> exit({:private, opts[:secret]})
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

  test "verification success emits only the invocation span with matching identity", %{tag: tag} do
    assert {:ok, _run} = run_with_verifier(:ok)
    events = collect(tag)
    run_id = assert_correlated(events)
    assert_verification(events, run_id, :stop, %{outcome: :ok, verification_status: :passed})
    assert select(events, :context) == []
    assert select(events, :guardrail) == []
  end

  test "returned verification failure preserves the raw result but emits only classification", %{
    tag: tag
  } do
    assert {:error, run} = run_with_verifier(:reject)
    assert %{secret: @secret, trace: [_ | _]} = run.verification_error
    events = collect(tag)
    run_id = assert_correlated(events)

    assert_verification(events, run_id, :stop, %{
      outcome: :error,
      verification_status: :failed,
      error_type: :verification_failed
    })
  end

  for {mode, kind} <- [raise: :error, throw: :throw, exit: :exit] do
    test "verification #{mode} emits exception and remains a runner crash", %{tag: tag} do
      capture_log(fn ->
        assert {:error, run} = run_with_verifier(unquote(mode))
        assert {:runner_crashed, _reason} = run.error
      end)

      events = collect(tag)
      run_id = assert_correlated(events)

      assert_verification(events, run_id, :exception, %{
        kind: unquote(kind),
        error_type: :exception
      })

      [{_, _, terminal}] = select(events, :run, :stop)
      assert terminal.error_type == :runner_crashed
    end
  end

  test "compression events match actual compression and contain only counts", %{tag: tag} do
    assert {:error, run} =
             API.run(@secret,
               llm: {BeamAgent.LLM.Mock, mode: :loop_forever},
               tools: %{echo: BeamAgent.Tools.Echo},
               guardrails: [max_iterations: 5, max_tool_calls: 10, max_context_messages: 4]
             )

    events = collect(tag)
    run_id = assert_correlated(events)
    compressed = select(events, :context, :compressed)
    assert length(compressed) > 0
    assert length(compressed) == Enum.count(run.trace, &(&1.type == :context_compressed))

    for {_, measurements, metadata} <- compressed do
      assert metadata == %{run_id: run_id, iteration: metadata.iteration}
      assert measurements.before_count > measurements.after_count
      assert measurements.after_count <= 4
      assert measurements.compressed_messages > 0
      assert measurements.summary_chars > 0

      assert_point(measurements, [
        :before_count,
        :after_count,
        :compressed_messages,
        :summary_chars
      ])
    end

    assert select(events, :context, :compression_failed) == []

    refute Enum.any?(select(events, :guardrail), fn {_, _, metadata} ->
             metadata.guardrail == :max_context_messages
           end)

    assert select(events, :verification) == []
  end

  for {limit, iteration, observed} <- [{0, 0, 1}, {1, 1, 3}, {2, 1, 3}] do
    test "context cap #{limit} blocks execution with one rejection when compression fails", %{
      tag: tag
    } do
      assert {:error, run} =
               API.run(@secret,
                 llm: {BeamAgent.LLM.Mock, []},
                 tools: %{echo: BeamAgent.Tools.Echo},
                 guardrails: [max_context_messages: unquote(limit)]
               )

      assert {:context_limit_too_small, %{configured: unquote(limit), minimum: 3}} = run.error
      events = collect(tag)
      run_id = assert_correlated(events)

      [{[:beam_agent, :context, :compression_failed], measurements, metadata}] =
        select(events, :context)

      assert metadata == %{
               run_id: run_id,
               iteration: unquote(iteration),
               error_type: :context_limit_too_small
             }

      assert measurements.configured_max_messages == unquote(limit)
      assert measurements.minimum_messages == 3
      assert_point(measurements, [:configured_max_messages, :minimum_messages])
      [{_, rejection, classification}] = select(events, :guardrail)

      assert classification == %{
               run_id: run_id,
               iteration: unquote(iteration),
               guardrail: :max_context_messages,
               phase: :context,
               unit: :count
             }

      assert rejection.observed == unquote(observed)
      assert rejection.limit == unquote(limit)
      assert_point(rejection, [:observed, :limit])
      assert select(events, :verification) == []
      assert length(select(events, :run, :stop)) == 1
    end
  end

  test "a small cap remains valid when execution never needs compression", %{tag: tag} do
    assert {:ok, _run} =
             API.run(@secret,
               llm: {BeamAgent.LLM.Mock, mode: :hallucinate_success},
               guardrails: [max_context_messages: 1]
             )

    events = collect(tag)
    assert_correlated(events)
    assert select(events, :context) == []
    assert select(events, :guardrail) == []
  end

  for {options, guardrail, phase, unit, iteration} <- [
        {[max_iterations: 0], :max_iterations, :before_step, :count, 0},
        {[max_iterations: 1], :max_iterations, :before_tool, :count, 1},
        {[max_tool_calls: 0], :max_tool_calls, :before_tool, :count, 1},
        {[max_execution_time_ms: 0], :max_execution_time, :before_step, :millisecond, 0}
      ] do
    test "#{guardrail} at #{phase} emits exactly one rejection", %{tag: tag} do
      assert {:error, _run} =
               API.run(@secret,
                 llm: {BeamAgent.LLM.Mock, []},
                 tools: %{echo: BeamAgent.Tools.Echo},
                 guardrails: unquote(options)
               )

      events = collect(tag)
      run_id = assert_correlated(events)
      [{_, measurements, metadata}] = select(events, :guardrail)

      assert metadata == %{
               run_id: run_id,
               iteration: unquote(iteration),
               guardrail: unquote(guardrail),
               phase: unquote(phase),
               unit: unquote(unit)
             }

      assert measurements.observed >= measurements.limit
      assert_point(measurements, [:observed, :limit])
      assert select(events, :verification) == []
      assert select(events, :context) == []
    end
  end

  test "standalone checks are silent and the context rejection consumer preserves its result", %{
    tag: tag
  } do
    state = State.new(@secret)
    opts = [max_context_messages: 0]
    result = Guardrails.check_context(state, opts)
    assert {:error, {:max_context_messages_exceeded, _}} = result
    assert collect(tag) == []
    run_id = make_ref()
    assert GuardrailTelemetry.observe(result, state, opts, :context, run_id) == result
    [{_, measurements, metadata}] = collect(tag)

    assert metadata == %{
             run_id: run_id,
             iteration: 0,
             guardrail: :max_context_messages,
             phase: :context,
             unit: :count
           }

    assert measurements.observed == 1
    assert measurements.limit == 0
    assert_point(measurements, [:observed, :limit])

    assert :ok = GuardrailTelemetry.observe(:ok, state, [], :context, run_id)
    unknown = {:error, %{secret: @secret}}
    assert ^unknown = GuardrailTelemetry.observe(unknown, state, [], :context, run_id)
    assert collect(tag) == []
  end

  test "the time rejection consumer retains measured values at the before-tool boundary", %{
    tag: tag
  } do
    state = State.new(@secret)
    result = Guardrails.check_before_tool(state, max_execution_time_ms: 0)
    assert {:error, {:max_execution_time_reached, details}} = result
    run_id = make_ref()
    assert ^result = GuardrailTelemetry.observe(result, state, [], :before_tool, run_id)
    [{_, measurements, metadata}] = collect(tag)

    assert metadata == %{
             run_id: run_id,
             iteration: 0,
             guardrail: :max_execution_time,
             phase: :before_tool,
             unit: :millisecond
           }

    assert measurements.observed == details.elapsed_ms
    assert measurements.limit == details.maximum_ms
  end

  test "standalone compression and verification do not create run events", %{tag: tag} do
    context = Context.new(@secret) |> Context.add_user_message(@secret)
    assert {:error, _} = Context.compress(context, max_messages: 0)
    run = BeamAgent.Run.timeout(@secret, 1)
    assert {:error, _} = BeamAgent.Verifier.verify(run)
    assert collect(tag) == []
  end

  def handle_event(event, measurements, metadata, {owner, tag}) do
    send(owner, {tag, event, measurements, metadata})
  end

  defp run_with_verifier(mode) do
    API.run(@secret,
      llm: {BeamAgent.LLM.Mock, []},
      tools: %{echo: BeamAgent.Tools.Echo},
      verification: [module: Verifier, mode: mode, secret: @secret]
    )
  end

  defp collect(tag) do
    receive do
      {^tag, event, measurements, metadata} -> [{event, measurements, metadata} | collect(tag)]
    after
      0 -> []
    end
  end

  defp select(events, operation, phase \\ nil) do
    Enum.filter(events, fn {[:beam_agent, op, ph], _, _} ->
      op == operation and (is_nil(phase) or phase == ph)
    end)
  end

  defp assert_correlated(events) do
    [{_, _, %{run_id: run_id}}] = select(events, :run, :start)

    assert Enum.map(select(events, :run), fn {name, _, _} -> name end) == [
             [:beam_agent, :run, :start],
             [:beam_agent, :run, :stop]
           ]

    assert is_reference(run_id)
    assert Enum.all?(events, fn {_, _, metadata} -> metadata.run_id == run_id end)
    refute inspect(events) =~ @secret
    run_id
  end

  defp assert_verification(events, run_id, phase, expected) do
    [
      {[:beam_agent, :verification, :start], start, metadata},
      {[:beam_agent, :verification, ^phase], terminal, terminal_metadata}
    ] = select(events, :verification)

    assert metadata == %{run_id: run_id, telemetry_span_context: metadata.telemetry_span_context}
    assert is_reference(metadata.telemetry_span_context)
    [{_, _, run_metadata}] = select(events, :run, :start)
    refute metadata.telemetry_span_context == run_metadata.telemetry_span_context
    assert terminal_metadata == Map.merge(metadata, expected)
    assert Map.keys(start) |> Enum.sort() == [:monotonic_time, :system_time]
    assert Map.keys(terminal) |> Enum.sort() == [:duration, :monotonic_time]
    assert terminal.duration >= 0
    assert terminal.duration == terminal.monotonic_time - start.monotonic_time
  end

  defp assert_point(measurements, keys) do
    assert Map.keys(measurements) |> Enum.sort() ==
             Enum.sort(keys ++ [:system_time, :monotonic_time, :count])

    assert Enum.all?(measurements, fn {_, value} -> is_integer(value) end)
    assert measurements.count == 1
  end
end
