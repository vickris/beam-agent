# Elixir Code Review

Review the provided Elixir code against the following dimensions:

- correctness
- OTP semantics
- public API design
- types/specs
- failure handling
- test quality
- unnecessary dependencies
- architectural boundaries

## Review approach

1. Identify the primary behavior and intended contract.
2. Check whether the implementation actually satisfies that behavior.
3. Evaluate if the code follows OTP and Elixir conventions.
4. Inspect public interfaces for clarity, stability, and minimal scope.
5. Verify types, specs, and guards are accurate and useful.
6. Check error handling, supervision, retries, timeouts, and failure modes.
7. Assess test coverage and whether tests validate the important behaviors.
8. Look for unnecessary dependencies, hidden coupling, and boundary leaks.
9. Call out architectural issues that make the code hard to evolve or reason about.

## What to look for

### correctness
- Logic errors, edge-case bugs, and incorrect state transitions.
- Off-by-one errors, race conditions, incorrect pattern matching, and stale data reads.
- Mismatches between documented behavior and implementation.

### OTP semantics
- GenServer, Task, Supervisor, Registry, Application, and dynamic supervision patterns used correctly.
- State management is explicit and consistent.
- Processes are started, supervised, and terminated according to ownership and lifecycle rules.
- Avoid blocking work in GenServer callbacks unless intentionally designed.

### public API design
- APIs are small, clear, and coherent.
- Avoid leaking internal structs or implementation details.
- Prefer explicit, idiomatic Elixir function names and argument patterns.
- Keep public contracts stable and well-documented.

### types/specs
- Specs match actual runtime behavior and are meaningful.
- Types are not overly broad or misleading.
- Use @type, @spec, and @doc where they improve clarity.
- Avoid specs that are boilerplate without strengthening contract guarantees.

### failure handling
- Errors are handled deliberately: return values, `{:ok, value}` / `{:error, reason}`, exceptions, and exit semantics are appropriate.
- Timeouts, retries, and degraded behavior are considered.
- Data validation and invariants are checked before unsafe operations.
- Failure paths do not silently swallow important errors.

### test quality
- Tests cover the critical behaviors and edge cases.
- Assertions validate the actual contract, not incidental implementation details.
- Tests are deterministic and isolated.
- Missing tests for failure, concurrency, and boundary conditions are flagged.

### unnecessary dependencies
- New dependencies are justified by clear need.
- There is no overuse of libraries where stdlib or OTP would suffice.
- Dependencies do not bloat the app or create avoidable operational complexity.

### architectural boundaries
- Modules are cohesive and separated by responsibility.
- Business logic is not coupled to infrastructure or transport concerns.
- Avoid mixing persistence, process supervision, and domain logic in the same layer.
- Boundaries are explicit and testable.

## Output format

Provide a concise review with:

- summary of overall quality
- key findings ordered by severity
- for each finding: issue, why it matters, and suggested fix
- note any positive patterns or good design decisions

Focus on actionable feedback. Prefer concrete, code-level observations over vague criticism.
