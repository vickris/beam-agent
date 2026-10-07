# BeamAgent

BeamAgent is a reusable Elixir/OTP runtime for building tool-using AI agents.

The library provides the infrastructure for running an agent loop, interacting
with language models, executing tools, enforcing runtime guardrails, recording
execution traces, and verifying outcomes.

## Architectural principles

BeamAgent must remain application and domain agnostic.

Do not introduce shopping-specific, ecommerce-specific, or other
application-specific concepts into this repository.

Prefer behaviours and dependency injection when integrating external systems.

Prefer standard Elixir and OTP primitives before introducing new dependencies.

Long-lived processes must be part of an appropriate supervision tree.

Side-effecting operations must remain distinguishable from read-only operations.

Deterministic verification must not depend on an LLM deciding whether an
operation succeeded.

## Public APIs

Public modules and functions should have documentation where appropriate.

Public APIs should have typespecs.

Avoid exposing implementation details through public APIs unless necessary.

Changes to public APIs should preserve backwards compatibility unless the
change explicitly requires a breaking release.

## Error handling

Prefer explicit error tuples such as:

    {:ok, result}
    {:error, reason}

Do not silently swallow failures.

Failures should preserve enough information for callers and telemetry to
understand what happened.

## Testing

Behavioural changes require tests.

Tests should verify observable behaviour instead of implementation details
where practical.

Before considering work complete, run:

    mix format --check-formatted
    mix test

For substantial changes, run:

    mix precommit

## Planning

Substantial features, architecture changes, and significant refactors require
an implementation plan before coding begins.

Implementation plans live under:

    .agent/plans/

Follow the planning rules defined in:

    .agent/PLANS.md

Small bug fixes and trivial changes do not require an implementation plan.

## Coding standards

Follow the conventions documented in:

    CODING_STANDARDS.md

## Completion criteria

Do not declare work complete merely because the code compiles.

Work is complete when:

1. The requested behaviour exists.
2. Relevant tests pass.
3. Repository guardrails pass.
4. Public APIs are documented where appropriate.
5. The implementation respects existing architectural boundaries.
