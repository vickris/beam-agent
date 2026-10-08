# Add Telemetry to BeamAgent

## Goal

Expose BeamAgent runtime activity through telemetry events so applications can
observe agent execution without coupling BeamAgent to a logging, metrics, or
monitoring backend.

Applications should be able to observe important lifecycle events such as:

- agent runs
- model calls
- tool execution
- verification
- context compression
- failures

Telemetry must remain optional. BeamAgent should continue working when no
telemetry handlers are attached.

## Non-goals

This plan does not implement:

- persistent trace storage
- OpenTelemetry export
- dashboards
- structured logging
- model cost accounting
- distributed tracing
- retry policies

Those may consume telemetry events later.

## Current architecture

Each BeamAgent execution runs in a temporary `BeamAgent.Runner` GenServer.

`BeamAgent.API.run/2` starts the runner through `BeamAgent.RunSupervisor`,
monitors it, and waits for a final result.

`Runner` performs model calls, tool execution, context compression, guardrail
checks, and verification within the same process.

Execution history is currently recorded as `%BeamAgent.Trace.Step{}` values in
the run state.

Trace events currently include model and tool activity but are stored only
inside the run and are unavailable to external observers while execution is
in progress.

## Constraints

- BeamAgent must remain monitoring-backend agnostic.
- Telemetry must not depend on Phoenix, Ecto, OpenTelemetry, or a specific
  metrics system.
- Instrumentation must not change BeamAgent's public execution semantics.
- Telemetry handlers must not be required for execution.
- Runtime instrumentation should add minimal overhead.
- Event names and metadata should form a stable, documented API.

## Proposed design

TBD after architecture review.

## Milestones

TBD.

## Failure semantics

Telemetry must not become part of the agent's business success criteria.

A monitoring failure must not convert a successful agent execution into a
failed execution.

Exact handler failure semantics will be documented after the implementation
approach is selected.

## Observability

Telemetry is itself the observability mechanism introduced by this plan.

Event naming, measurements, and metadata must be documented as part of the
public instrumentation contract.

## Testing strategy

Tests should verify that expected telemetry events are emitted with appropriate
metadata and measurements.

Tests should not depend on global handlers shared across concurrent tests.

Telemetry tests must clean up attached handlers.

## Rollout / compatibility

Telemetry is additive and should not require changes from existing BeamAgent
users.

## Validation

    mix format --check-formatted
    mix test
    mix precommit

## Progress

- [x] Implement Milestone 1: telemetry foundation and internal run correlation.
- [x] Validate Milestone 1 formatting and tests: `mix format --check-formatted`
      passed; `mix test` passed with 29 tests, including 8 new infrastructure tests.
- [ ] Complete Milestone 1 validation with `mix precommit`: attempted, but Mix
      reports that the task could not be found. The required guardrail remains blocked.
- [ ] Design telemetry event contract
- [x] Implement Milestone 2 run lifecycle events owned by `API.run/2`.
- [x] Validate Milestone 2 with `mix test`: 41 tests passed, including 12 new
      tests for lifecycle events and classification allowlists. `git diff --check`
      passed.
- [ ] Complete Milestone 2 required validation: `mix precommit` still reports
      that the task could not be found. The separate full formatting check also
      fails on pre-existing formatting in `mix.exs`; that file remains unchanged.
- [ ] Instrument model calls
- [ ] Instrument tools
- [x] Instrument verification (Milestone 4): configured invocation only, with
      sanitized start/stop/exception events and unchanged return/escape behavior.
- [x] Instrument context compression (Milestone 4): actual compression and
      explicit compression failure events; no-op preparation remains silent.
- [x] Instrument guardrail rejection (Milestone 4) at the three consumption
      boundaries; successful checks and failure propagation remain silent.
- [x] Validate Milestone 4 with `mix test`: 57 tests passed, including 16 new
      tests. `git diff --check` passed.
- [x] Fix context-limit rejection coverage: unrecoverable compression now emits
      one context guardrail rejection while preserving the original failure.
      Follow-up validation: 60 tests passed, scoped formatting and
      `git diff --check` passed; the existing global validation blockers remain.
- [ ] Complete Milestone 4 required validation: `mix precommit` still reports
      that the task could not be found. The full formatting check fails on the
      existing `mix.exs` formatting; this milestone leaves that file unchanged.
- [x] Document the implemented telemetry contract in `docs/telemetry.md` and
      link it from the README and generated documentation.
- [x] Complete Milestone 5 contract validation: strengthen the observed run
      event sequence assertion, register the existing precommit alias, and pass
      `mix precommit` (60 tests, 0 failures) and `git diff --check`.

## Decisions

### Milestone 5 documents the emitted contract

Decision:

Document only the nine emitted event names: run and verification start/stop/
exception, context compressed/compression_failed, and guardrail rejected.
The planned model/tool spans are not implemented. The verifier span does not
emit `verifier_module`. Context compression failure also emits a context
guardrail rejection when the message limit blocks recovery. The reference
specifies the exact current fields, finite classifications, native time units,
correlation, and handler behavior.

Reason:

The draft reference and original plan included future fields and events.
Changing runtime behavior for parity would extend this documentation milestone
into instrumentation work. Existing tests already assert exact field sets,
classification filtering, correlation, sensitive-data exclusion, and span
terminal uniqueness; the added sequence assertion protects the run event names
and terminal count across the runtime telemetry scenarios.

The existing `precommit` alias was defined but not registered in `mix.exs`.
Register it with the test environment and format the file so the required
validation command runs. Include the telemetry reference in generated docs and
the package, making the published contract accessible to users.


### Introduce an ephemeral run ID for telemetry correlation

Decision:

Generate an opaque run identifier before runner startup and pass it explicitly
into the runner.

The initial implementation may use an Erlang reference:

    make_ref()

The identifier exists only for runtime correlation between telemetry emitted
by `BeamAgent.API` and `BeamAgent.Runner`.

It is not currently:

- a persistent identifier
- a registry key exposed to applications
- a distributed trace identifier
- a caller-supplied identifier
- part of the public `%BeamAgent.Run{}` contract

Reason:

Using the Runner PID would couple run identity to process identity and would
provide no correlation identifier for runner startup failures.

Introducing correlation identity now also allows telemetry from concurrent
runs to be distinguished without prematurely designing the future run registry.

Future work may introduce a durable/public run identifier as part of
Registry-based run lookup or persistent execution storage.

### Milestone 1 foundation boundary

Decision:

Add the standard `:telemetry` runtime dependency and an internal
`BeamAgent.Telemetry.execute/3` emission boundary. No runtime instrumentation
or span helper is introduced in this milestone.

The initial metadata allowlist contains only `:run_id` and
`:telemetry_span_context`, both restricted to references. Measurements are
restricted to integer `:system_time`, `:monotonic_time`, `:duration`, and
`:count` values. Unknown keys and invalid values are omitted. Future fields
must be added with their event contracts instead of forwarding arbitrary maps.

Reason:

Key filtering alone could leak execution content hidden under an allowed key.
Value checks provide a small, explicit boundary without prematurely defining
later instrumentation. Handlers are optional; the interoperable dependency is
always available. A custom event bus or monitoring process is unnecessary.

### Carry correlation through existing startup options

Decision:

`API.run/2` generates a fresh reference before `RunSupervisor.start_run/1`,
overriding any supplied `:run_id`. The existing options path carries it to
`Runner.init/1`, which retains it in the private GenServer state. Direct
`Runner.start_link/1` calls generate a fallback reference before process startup
when the internal option is absent. The public `Run` struct is unchanged.

Reason:

This preserves existing direct startup calls and requires no supervisor changes,
registry, process dictionary, or new public configuration. Tests observe the
startup boundary with scoped Erlang call tracing and inspect idle runner state;
production test hooks and runtime telemetry events are not needed.

### Preserve the existing validation configuration

Decision:

Record the missing `mix precommit` task as a validation blocker rather than
adding an alias or substituting a different command in this milestone.

Reason:

The task is required by the plan but is not defined by the repository. Defining
its checks is separate from telemetry foundation work; formatting and the full
test suite passed, but they do not establish that this missing guardrail passed.

### Milestone 2 API-owned run span

Decision:

Create the existing ephemeral run ID and a distinct span reference at API entry,
before option processing or runner startup. Emit start in the caller, then one
stop for a normal return or one exception for an escaping error, throw, or exit.
Use API-local monotonic timestamps in native units, independently of
`Run.duration_ms`, so verification and timeout cleanup remain inside the span.

Reason:

The caller can observe startup failures and runner termination. Instrumenting
the runner instead would lose terminal events on hard timeout. External caller
termination can still prevent a terminal event; telemetry is not durable storage.

### Preserve returns while classifying failures

Decision:

Keep the existing startup failure output and `:ok` return, but emit stop with
`outcome: :error`, unknown statuses, and `error_type: :startup_failed`. Completed
run results retain their original values; handled runner crashes and hard
timeouts emit stop. Unknown execution errors use `:execution_failed`, verifier
rejections use `:verification_failed`, and unexpected result messages are
returned unchanged with an `:unexpected_result` classification.

Escaping errors, throws, and exits emit only correlation references,
`error_type: :exception`, and finite `:kind`, then are re-raised with the original
reason and stacktrace. Raw reasons and stacktraces never enter telemetry.

Reason:

Telemetry must not fix the known startup return-contract issue, leak execution
content, or convert exceptions into successful returns. Field-specific finite
allowlists admit only run outcome/status/error classifications. Counters are
included only when integer values are available; crash and timeout results do
not acquire invented counts. Tests cover both return paths and all three escape
kinds, matching IDs, durations, privacy, verification lifetime, and concurrency.

### Milestone 4 invocation and rejection boundaries

Decision:

Thread the existing run ID through private runner calls without changing the
public Run or execution State structs. Wrap only the configured verifier's
`verify/2` invocation, after constructing its candidate and before interpreting
its result. Returned failures emit stop with `:verification_failed`; escaping
errors, throws, and exits emit sanitized exception metadata and are re-raised.
Metadata contains correlation references and bounded outcome/status/error
classifications, with no verifier payload or module field needed in this scope.

Emit context points only at actual compression or its explicit failure branch.
The existing second context preparation and all runtime check ordering remain
unchanged. A shared internal point emitter supplies native timestamps and
`count: 1`; context measurements select documented numeric fields only.

Reason:

The events must describe work already performed without expanding their scope
to result construction, verification decisions, or unrelated runtime changes.
Standalone verifier and context calls remain uninstrumented, and execution
failures never start verification spans.

### Guardrail rejection projection and failed context recovery

Decision:

Use internal `BeamAgent.Guardrails.Telemetry.observe/5` at the runner's
before-step, before-tool, and post-compression context checks. It returns the
original result and projects only known failures into documented numeric
measurements and finite guardrail/phase/unit metadata. Unknown reasons are not
emitted. Guardrail modules themselves remain silent.

Reason:

One consumption-boundary emission avoids double counting when failures are
propagated. The current compressor ensures the message bound whenever it
succeeds, so the separate max-context rejection cannot normally be triggered
through `API.run/2`. Its mapping is tested using a real over-limit
`Guardrails.check_context/2` result passed through the same observation helper,
without altering runtime behavior to make that branch reachable.

Follow-up decision: when `:context_limit_too_small` prevents recovery, consume
`Guardrails.check_context/2` at the compression failure boundary and emit one
context guardrail rejection. Keep the compression failure event to describe the
failed recovery attempt. The guardrail event measures actual rendered messages
against the configured cap, not the compressor's minimum capacity. Preserve the
original returned error and do not reject small caps before compression is
needed. Successful compression remains recovery, so it emits no rejection.
This replaces the earlier choice to emit only a context failure in this branch.
Acceptance covers caps 0, 1, and 2, including failure after a tool call, matching
run IDs, exactly one rejection, no verification, and a small-cap successful run.
Validation: `mix precommit`, `mix format --check-formatted`, `mix test`, and
`git diff --check`.

## Open questions

- Which events should use `:telemetry.span/3` versus `:telemetry.execute/3`?
- Should telemetry event names live under `[:beam_agent, ...]`?
- Which identifiers belong in metadata?
- Should `run_id` be introduced as part of this change or deferred to the
  run-registry milestone?
- Which data belongs in measurements versus metadata?
- Should existing internal trace events map one-to-one to telemetry events?

### Keep execution traces and telemetry independent

Decision:

`BeamAgent.Trace` and BeamAgent telemetry remain separate abstractions.

Telemetry must not be emitted automatically from `Trace.record/4`, and trace
events do not need a one-to-one telemetry equivalent.

Reason:

Trace is detailed execution evidence retained by BeamAgent.

Telemetry is a live observability interface with bounded and explicitly
allowlisted metadata.

Trace payloads may contain tool arguments, results, and execution content that
must not be exposed through telemetry.

Verification may continue to inspect trace evidence and must never depend on
telemetry delivery.

## Milestone 2 — Run lifecycle telemetry

### Objective

Instrument the complete `BeamAgent.API.run/2` lifecycle.

The run span must cover startup, execution, verification, crash handling,
timeout handling, and final result delivery.

### Expected changes

Emit:

    [:beam_agent, :run, :start]
    [:beam_agent, :run, :stop]
    [:beam_agent, :run, :exception]

The API layer owns the span because it can observe startup failures, runner
crashes, and forced timeout termination.

### Start event

Measurements:

- system_time
- monotonic_time

Metadata:

- run_id
- telemetry_span_context

### Stop event

Measurements:

- duration
- monotonic_time
- iterations when available
- tool_calls when available

Metadata:

- run_id
- telemetry_span_context
- outcome
- execution_status
- verification_status
- error_type when applicable

Handled BeamAgent errors, runner crashes, and execution timeouts emit `:stop`
with `outcome: :error`.

### Exception event

Emit only when an error, throw, or exit escapes the API run boundary rather
than being converted into a BeamAgent result.

Raw error reasons and stacktraces must not be included in telemetry metadata.

### Acceptance criteria

- Every normal run emits exactly one start event and one terminal event.
- Start and terminal events use the same run ID.
- Start and terminal events use the same telemetry span context.
- Successful runs report `outcome: :ok`.
- Verification failures report `outcome: :error`.
- Runner crashes are classified without exposing raw exceptions.
- Hard execution timeouts are classified as `:execution_timeout`.
- Startup failures are classified without exposing raw reasons.
- No prompts, answers, model responses, tool arguments, or tool results appear
  in metadata.
- Existing BeamAgent return values remain unchanged.
- Existing tests remain green.

### Validation

    mix precommit
    git diff --check

## Milestone 4 — Verification, context, and guardrail telemetry

### Objective

Complete BeamAgent runtime instrumentation for verification, context
compression, and guardrail rejection.

### Verification events

Emit:

    [:beam_agent, :verification, :start]
    [:beam_agent, :verification, :stop]
    [:beam_agent, :verification, :exception]

The span wraps only the configured verifier invocation.

Metadata may include:

- run_id
- telemetry_span_context
- verifier_module
- outcome
- verification_status
- kind
- error_type

No trace contents, answer content, verifier reason, or Run struct may be
included.

No verification span should be emitted if execution fails before verification.

### Context events

Emit:

    [:beam_agent, :context, :compressed]
    [:beam_agent, :context, :compression_failed]

Emit `:compressed` only when compression actually changes context.

Measurements may include:

- system_time
- monotonic_time
- count
- before_count
- after_count
- compressed_messages
- summary_chars
- configured_max_messages
- minimum_messages

Metadata may include:

- run_id
- iteration
- error_type

Do not emit context messages or summary contents.

### Guardrail event

Emit:

    [:beam_agent, :guardrail, :rejected]

Emit only when execution is blocked by a guardrail.

Measurements may include:

- system_time
- monotonic_time
- count
- observed
- limit

Metadata may include:

- run_id
- iteration
- guardrail
- phase
- unit

Guardrail, phase, and unit must use finite documented vocabularies.

### Acceptance criteria

- Verification emits matching start/terminal span events.
- Verification failures use bounded classifications.
- Context compression emits only when meaningful work occurs.
- Compression failures do not expose context content.
- Guardrail success emits no event.
- Guardrail rejection emits exactly one event for the rejecting check.
- All events reuse the current run_id.
- Sensitive execution content is excluded.
- Existing runtime behavior remains unchanged.

## Milestone 5 — Documentation and contract validation

### Objective

Document BeamAgent's telemetry interface and protect its public observability
contract from accidental drift.

No new runtime instrumentation is introduced by this milestone.

### Documentation

Add a telemetry reference documenting:

- event names
- emission semantics
- measurements
- metadata
- correlation identifiers
- failure semantics
- sensitive-data exclusions
- handler execution behavior

Clearly distinguish telemetry from `BeamAgent.Trace`.

### Contract validation

Add or strengthen tests protecting:

- event names
- allowed metadata fields
- allowed measurement fields
- bounded classification values
- correlation between start and terminal events
- absence of sensitive execution content
- absence of duplicate terminal events

Tests should fail if future instrumentation accidentally exposes prompts,
responses, tool arguments, tool results, raw exceptions, or other
execution content.

### Acceptance criteria

- All currently supported events are documented.
- Measurement and metadata contracts are documented.
- Sensitive-data exclusions are explicit.
- Trace and telemetry responsibilities are clearly distinguished.
- Handler execution semantics are documented.
- Contract tests protect the documented schema.
- No new runtime behavior is introduced.
- All previous telemetry tests remain green.

### Validation

    mix precommit
    git diff --check
