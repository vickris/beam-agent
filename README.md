# BeamAgent

A general-purpose Elixir agent harness — the LLM tool-use loop, guardrails,
and verification other developers can build agents on top of (a shopping
agent, a research agent, a coding agent, a workflow or internal-automation
agent, etc.). Named `BeamAgent` rather than `Agent` to avoid colliding with
Elixir's own stdlib `Agent` module.

Elixir was chosen for the BEAM properties:

- **Isolated processes** — each agent run is its own `GenServer`, so one
  run crashing (a tool raising, for example) has no effect on any other.
- **Supervision** — every run is started under a `DynamicSupervisor`, so
  cleanup on completion, failure, or crash is automatic and any number of
  runs can be active concurrently.
- **OTP behaviours** — pluggable pieces (`BeamAgent.LLM.Client`,
  `BeamAgent.Tools.Behaviour`, `BeamAgent.Verifier.Behaviour`) are plain
  Elixir behaviours, not a bespoke plugin system.
- **Message passing** keeps tool execution and the call/reply protocol
  between a run and its caller clean and easy to reason about.

## Usage

```elixir
BeamAgent.API.run(
  "Find the cheapest supermarket for a weekly shop",
  llm: {MyApp.LLMClient, model: "..."},
  tools: %{price_check: MyApp.Tools.PriceCheck},
  guardrails: [max_iterations: 8, max_execution_time_ms: 30_000],
  verification: [required_tools: [:price_check]]
)
#=> {:ok, %BeamAgent.Run{}} | {:error, %BeamAgent.Run{}}
```

`{:ok, run}` only when the run finished *and* verification passed;
everything else — a guardrail tripped, an unknown tool, a hard timeout, a
runner crash, or verification failing a plausible-looking answer — comes
back as `{:error, run}` with the reason on `run`. Every `run.trace` entry is
retained either way, so a failure is fully inspectable, not just a bare
error atom.

To plug in a real model, implement `BeamAgent.LLM.Client`
(`chat/2 :: {:reply, text} | {:tool_call, atom, map}`). To add a tool,
implement `BeamAgent.Tools.Behaviour` and pass it in the `:tools` map —
tools aren't hardcoded into the harness, each run supplies its own.

## Lifecycle and supervision

`BeamAgent.API.run/2` starts one `BeamAgent.Runner` under
`BeamAgent.RunSupervisor` and blocks the caller until a result is ready.
Runs are `restart: :temporary` — a finished, failed, or crashed run is a
terminal result to hand back to the caller, not a transient failure to
retry, so there is no automatic restart.

See the [telemetry reference](docs/telemetry.md) for the supported events and
their measurement, metadata, and privacy contract.

Two independent time limits can race, by design:

- `BeamAgent.Guardrails`' `MaxExecutionTime` check runs *between* steps and
  tool calls — graceful, produces a normal `:max_execution_time_reached`
  failure once the runner notices.
- A tool call itself can't be preempted mid-flight (e.g. a tool blocking on
  slow I/O). `BeamAgent.API.run/2` is the backstop: after
  `max_execution_time_ms` plus a grace period it force-terminates the
  runner and returns a `:execution_timeout` result instead.

## Notable features

- Deterministic context compression (`BeamAgent.Context`) — no LLM call
  involved — that keeps the model-facing message count bounded as a run
  goes on, folding aged-out messages into a running summary rather than
  dropping them.
- Four independent, individually configurable guardrails: max iterations,
  max context messages, max execution time, max tool calls.
- Post-run verification (`BeamAgent.Verifier`) that catches a model
  claiming success without actually calling the tools it needed to —
  pluggable via `BeamAgent.Verifier.Behaviour` for domain-specific checks.
- A full execution trace on every run, success or failure.
- Standard Elixir/OTP primitives, with `:telemetry` for optional runtime
  observation.

## Development

```bash
mix deps.get    # fetch dependencies
mix compile      # compile
mix test          # run the full test suite
mix format          # format per .formatter.exs
```
