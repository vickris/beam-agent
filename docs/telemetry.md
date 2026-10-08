# Telemetry reference

BeamAgent emits the events below through the `:telemetry` library. Attaching a
handler is optional. Timestamp and duration fields use `System`'s `:native`
unit; convert them with `System.convert_time_unit/3` before displaying
milliseconds. The execution-time guardrail's `observed` and `limit` values use
milliseconds, as indicated by `unit: :millisecond`.
`system_time` is a wall-clock timestamp; `monotonic_time` and `duration` are
suited to elapsed-time calculations. Point events have `count: 1`.

## Correlation and failure semantics

Every event from one `BeamAgent.API.run/2` call has the same opaque `run_id`.
It is an Erlang reference generated before runner startup, including for runs
that fail to start. It is internal, ephemeral, and absent from `%BeamAgent.Run{}`.
Do not persist it as a durable or distributed trace ID or try to configure it
through run options.

Run and verification spans each have a `telemetry_span_context` reference. A
span's start and terminal events share that reference. Verification receives a
fresh reference distinct from the enclosing run span; use `run_id` to join
their events. Point events have no span context.

`:stop` means the instrumented operation returned, including a handled failure.
An error result from a verifier, a converted runner crash, and a hard timeout
are stops. `:exception` means an error, throw, or exit escaped that operation;
its `kind` classifies the escape, and the original reason is propagated. A
verification exception is emitted in the runner, which then crashes; the API
converts that crash into a run `:stop` with `error_type: :runner_crashed`.
External termination of the API caller can prevent its terminal event.

## Events

Every event name begins with `[:beam_agent]`. Fields listed as optional appear
only when the corresponding value is available or relevant. No other metadata
or measurements are emitted by the runtime for these events.

### Run lifecycle

`[:beam_agent, :run, :start]` is emitted on entry to `BeamAgent.API.run/2`,
before runner startup.

- Measurements: `system_time`, `monotonic_time`.
- Metadata: `run_id`, `telemetry_span_context`.

`[:beam_agent, :run, :stop]` is emitted when `API.run/2` returns normally,
including handled errors, failed verification, runner crashes, and hard
timeouts. The duration includes startup, execution, verification, and timeout
cleanup; it does not come from `Run.duration_ms`.

- Measurements: `monotonic_time`, `duration`; `iterations` and `tool_calls` when
  a `%BeamAgent.Run{}` supplies them.
- Metadata: `run_id`, `telemetry_span_context`, `outcome` (`:ok` or `:error`),
  `execution_status` (`:finished`, `:failed`, or `:unknown`),
  `verification_status` (`:passed`, `:failed`, `:not_run`, or `:unknown`), and
  `error_type` on errors.
- Run `error_type` values: `:startup_failed`, `:verification_failed`,
  `:execution_failed`, `:runner_crashed`, `:execution_timeout`, `:unknown_tool`,
  `:max_iterations_reached`, `:max_tool_calls_reached`,
  `:max_execution_time_reached`, `:max_context_messages_exceeded`,
  `:context_limit_too_small`, `:unexpected_result`.

`[:beam_agent, :run, :exception]` is emitted when an error, throw, or exit
escapes `API.run/2`.

- Measurements: `monotonic_time`, `duration`.
- Metadata: `run_id`, `telemetry_span_context`, `error_type: :exception`, and
  `kind` (`:error`, `:throw`, or `:exit`).

### Verification

These events surround only the configured verifier module's `verify/2` call.
Building its candidate run and interpreting its return are outside the span.
Execution failures that never reach verification emit no verification events.

`[:beam_agent, :verification, :start]`:

- Measurements: `system_time`, `monotonic_time`.
- Metadata: `run_id`, `telemetry_span_context`.

`[:beam_agent, :verification, :stop]` is emitted for any returned value.

- Measurements: `monotonic_time`, `duration`.
- Metadata: `run_id`, `telemetry_span_context`, `outcome`,
  `verification_status`, and `error_type` on failure.
- Returned `:ok` gives `outcome: :ok`, `verification_status: :passed`.
  `{:error, reason}` gives `outcome: :error`, `verification_status: :failed`,
  `error_type: :verification_failed`. Any other return gives `outcome: :error`,
  `verification_status: :unknown`, `error_type: :unexpected_result`.

`[:beam_agent, :verification, :exception]` is emitted for an error, throw, or
exit escaping the configured verifier.

- Measurements: `monotonic_time`, `duration`.
- Metadata: `run_id`, `telemetry_span_context`, `error_type: :exception`, and
  `kind` (`:error`, `:throw`, or `:exit`).

### Context compression

`[:beam_agent, :context, :compressed]` is emitted only when compression
actually changes the model-facing context. A context already within its limit
is silent.

- Measurements: `system_time`, `monotonic_time`, `count`, `before_count`,
  `after_count`, `compressed_messages`, `summary_chars`.
- Metadata: `run_id`, `iteration`.

`[:beam_agent, :context, :compression_failed]` is emitted when the configured
message limit is too small for required context slots at the point compression
is needed.

- Measurements: `system_time`, `monotonic_time`, `count`,
  `configured_max_messages`, `minimum_messages`.
- Metadata: `run_id`, `iteration`, `error_type: :context_limit_too_small`.

This failure also emits one context guardrail rejection. A small limit that
never requires compression can still complete without either event.

### Guardrail rejection

`[:beam_agent, :guardrail, :rejected]` is emitted when a runtime guardrail
blocks execution. Checks that pass are silent. An unrecoverable context
compression failure emits one rejection for the unsatisfied message limit.

- Measurements: `system_time`, `monotonic_time`, `count`, `observed`, `limit`.
- Metadata: `run_id`, `iteration`, `guardrail`, `phase`, `unit`.
- `guardrail`: `:max_iterations`, `:max_tool_calls`,
  `:max_context_messages`, or `:max_execution_time`.
- `phase`: `:before_step`, `:before_tool`, or `:context`.
- `unit`: `:count` or `:millisecond`. Context, iteration, and tool-call limits
  use `:count`; execution time uses `:millisecond`.

`observed` is the actual count or elapsed time at the rejecting check;
`limit` is the configured maximum. For a compression failure, `observed` is
the current rendered message count and `limit` is the configured message cap,
which differs from the compressor's `minimum_messages` requirement.

There are currently no model-call or tool-execution telemetry events.

## Data and handlers

Telemetry contains bounded classifications and numeric measurements. It does
not contain goals, prompts, model messages or responses, tool arguments or
results, context summaries, full State/Run/Trace structs, raw verification
reasons, raw exceptions, stacktraces, or provider configuration. The internal
emitter filters metadata by field-specific allowlists and measurement values
to integers. Handlers should still treat telemetry as application data and
avoid adding execution content when forwarding it.

`:telemetry` invokes handlers synchronously in the emitting process. Keep
handlers short; a slow handler delays the run or verifier. Telemetry detaches
a handler that raises, so handler failure does not become an agent failure.

`BeamAgent.Trace` serves a different purpose: `BeamAgent.Trace.Step` entries
form the detailed execution history retained in a returned run. Their payloads
can contain content such as tool arguments and results. Telemetry is a live,
sanitized observation stream and has no one-to-one mapping to trace steps.
Verification must rely on the run and its trace, not on telemetry delivery.

For example, attach a handler to completed runs:

```elixir
defmodule MyApp.RunObserver do
  def handle_event([:beam_agent, :run, :stop], measurements, metadata, _config) do
    send(MyApp.MetricsCollector, {:run_finished, metadata.run_id,
                                  metadata.outcome, measurements.duration})
  end
end

:telemetry.attach(
  "my-app-beam-agent-runs",
  [:beam_agent, :run, :stop],
  &MyApp.RunObserver.handle_event/4,
  nil
)

# Remove the handler when its owner shuts down:
:telemetry.detach("my-app-beam-agent-runs")
```

The receiver can convert the native duration to milliseconds and publish a
metric without blocking the runner on network I/O.
