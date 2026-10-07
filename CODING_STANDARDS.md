# BeamAgent Coding Standards

These conventions apply to Elixir code in BeamAgent.

## General

Prefer clear and explicit code over clever abstractions.

Keep functions focused on one responsibility.

Prefer small modules with clear ownership over large modules containing
unrelated responsibilities.

Avoid abstractions until there is a concrete reason for them.

## Pattern matching

Prefer pattern matching over deeply nested conditionals.

Prefer:

    def handle_result({:ok, result}), do: ...
    def handle_result({:error, reason}), do: ...

over branching on tuple contents manually.

## Control flow

Use `with` when several operations form a success pipeline and each operation
can fail.

Example:

    with {:ok, response} <- call_model(state),
         {:ok, action} <- parse_response(response),
         {:ok, state} <- execute_action(state, action) do
      {:ok, state}
    end

Avoid excessively long `with` expressions. Extract meaningful operations into
named functions.

## Error tuples

Use conventional result tuples:

    {:ok, value}
    {:error, reason}

Prefer meaningful error atoms or structured errors over arbitrary strings.

Example:

    {:error, :max_iterations}

rather than:

    {:error, "Something went wrong"}

when the failure is programmatically meaningful.

## OTP

Processes should have clearly defined ownership and responsibilities.

Do not use a GenServer merely to store state if another data structure or
abstraction is more appropriate.

Do not perform unnecessary blocking work inside GenServer callbacks.

Long-lived processes must be supervised.

Consider restart semantics when adding processes to the supervision tree.

## Configuration

Avoid reading application configuration throughout business logic.

Resolve configuration at system boundaries and pass required values explicitly
where practical.

## Dependencies

Do not introduce a dependency when the functionality can reasonably be
implemented using Elixir/OTP.

New dependencies should have a clear reason for inclusion.

## Tests

Test public behaviour rather than private implementation details.

Prefer deterministic tests.

Do not use arbitrary sleeps to synchronize concurrent tests.

Use process monitoring, messages, eventually-style helpers, or other
deterministic synchronization mechanisms instead.

## Documentation

Public modules should explain their responsibility.

Document important invariants and non-obvious design decisions.

Avoid comments that merely restate the code.

## Formatting

Code must pass:

    mix format --check-formatted
