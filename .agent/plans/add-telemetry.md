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

- [ ] Design telemetry event contract
- [ ] Instrument run lifecycle
- [ ] Instrument model calls
- [ ] Instrument tools
- [ ] Instrument verification
- [ ] Instrument context compression
- [ ] Document events

## Decisions

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
