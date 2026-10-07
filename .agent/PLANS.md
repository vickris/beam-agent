# BeamAgent Implementation Plans

Substantial features, architectural changes, and significant refactors should
be implemented from an ExecPlan.

ExecPlans live in:

    .agent/plans/

A plan is a living engineering document. It should be updated as implementation
progresses and as new information is discovered.

## When a plan is required

Create an ExecPlan for:

- new runtime capabilities
- significant OTP architecture changes
- changes affecting public APIs
- persistence or external integrations
- concurrency or distributed-system changes
- features requiring multiple implementation steps
- refactors that change ownership or responsibility between modules

Small bug fixes and trivial changes do not require a plan.

## Required sections

Each ExecPlan should contain the following sections.

### Goal

Describe the user-visible or system-visible outcome.

Explain why the change exists.

### Non-goals

Explicitly list related work that is outside the scope of this plan.

This prevents the implementation from expanding unnecessarily.

### Current architecture

Describe the parts of the existing system relevant to the change.

Reference concrete modules and functions.

Do not describe hypothetical architecture here.

### Constraints

List architectural, compatibility, OTP, performance, or API constraints that
the implementation must respect.

### Proposed design

Describe the intended architecture.

Include module boundaries, behaviours, important data structures, process
ownership, and relevant message flows.

Avoid specifying implementation details that are not necessary to constrain
the design.

### Milestones

Split implementation into independently verifiable milestones.

Each milestone must include:

- objective
- expected changes
- acceptance criteria
- validation commands

A milestone should produce a coherent repository state.

### Failure semantics

Describe important failure cases.

Explain:

- what can fail
- where failures are handled
- whether operations are retried
- what state is preserved
- what callers observe

### Observability

Describe relevant logging, telemetry, tracing, or metrics.

If observability is not applicable, state why.

### Testing strategy

Describe the important behaviours that must be tested.

Prefer observable behaviour over implementation-detail assertions.

Include concurrency and failure-path tests where relevant.

### Rollout / compatibility

Describe compatibility concerns for public APIs or persisted data.

If there are none, state that explicitly.

### Validation

List the final commands required before completion.

At minimum:

    mix format --check-formatted
    mix test
    mix precommit

### Progress

Track completed milestones.

Example:

    - [x] Define storage behaviour
    - [ ] Implement in-memory adapter
    - [ ] Integrate with Runner

### Decisions

Record meaningful implementation decisions discovered during the work.

Each decision should include:

- decision
- reason
- alternatives considered when relevant

### Open questions

Track unresolved questions that could affect later milestones.
