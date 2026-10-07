defmodule BeamAgent.TelemetryTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias BeamAgent.Telemetry

  @event [:beam_agent, :foundation_test]

  test "emits only explicitly allowed metadata and measurements" do
    tag = attach([@event])
    run_id = make_ref()
    span_context = make_ref()
    secret = "sensitive execution content"

    metadata = %{
      run_id: run_id,
      telemetry_span_context: span_context,
      goal: secret,
      prompt: secret,
      messages: [secret],
      arguments: %{secret: secret},
      result: secret,
      response: secret,
      state: BeamAgent.State.new(secret),
      run: BeamAgent.Run.timeout(secret, 1),
      reason: RuntimeError.exception(secret),
      stacktrace: [{__MODULE__, :example, [secret], []}],
      future_field: secret
    }

    assert :ok =
             Telemetry.execute(
               [:foundation_test],
               %{count: 1, duration: 42, system_time: 100, monotonic_time: -10, result: secret},
               metadata
             )

    assert_receive {^tag, @event, measurements, emitted_metadata}
    assert measurements == %{count: 1, duration: 42, system_time: 100, monotonic_time: -10}
    assert emitted_metadata == %{run_id: run_id, telemetry_span_context: span_context}
  end

  test "rejects payloads hidden under allowed field names" do
    tag = attach([@event])
    payload = %{prompt: "secret"}

    assert :ok =
             Telemetry.execute(
               [:foundation_test],
               %{duration: payload, count: "secret", system_time: [], monotonic_time: payload},
               %{run_id: payload, telemetry_span_context: RuntimeError.exception("secret")}
             )

    assert_receive {^tag, @event, %{} = measurements, %{} = metadata}
    assert measurements == %{}
    assert metadata == %{}
  end

  test "works without attached handlers" do
    assert :ok = Telemetry.execute([:unobserved_foundation_test], %{count: 1}, %{})
  end

  test "a failing handler does not propagate its exception" do
    handler_id = {__MODULE__, make_ref()}
    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert :ok = :telemetry.attach(handler_id, @event, &__MODULE__.fail/4, nil)

    capture_log(fn ->
      assert :ok = Telemetry.execute([:foundation_test], %{count: 1}, %{})
    end)

    refute Enum.any?(:telemetry.list_handlers(@event), &(&1.id == handler_id))
  end

  test "the runtime does not emit instrumentation yet" do
    spans =
      for operation <- [:run, :model, :tool, :verification],
          phase <- [:start, :stop, :exception],
          do: [:beam_agent, operation, phase]

    points = [
      [:beam_agent, :context, :compressed],
      [:beam_agent, :context, :compression_failed],
      [:beam_agent, :guardrail, :rejected]
    ]

    tag = attach(spans ++ points)

    assert {:ok, _run} =
             BeamAgent.API.run("hello",
               llm: {BeamAgent.LLM.Mock, []},
               tools: %{echo: BeamAgent.Tools.Echo}
             )

    refute_received {^tag, _, _, _}
  end

  def handle_event(event, measurements, metadata, {owner, tag}) do
    send(owner, {tag, event, measurements, metadata})
  end

  def fail(_event, _measurements, _metadata, _config) do
    raise "test handler failure"
  end

  defp attach(events) do
    tag = make_ref()
    handler_id = {__MODULE__, tag}
    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok = :telemetry.attach_many(handler_id, events, &__MODULE__.handle_event/4, {self(), tag})
    tag
  end
end
