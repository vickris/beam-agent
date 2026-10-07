# Architecture

## Purpose and boundaries

BeamAgent is a domain-neutral Elixir/OTP harness for LLM-driven tool-use runs. It provides the run lifecycle, bounded model context, guardrails, pluggable tools and LLM clients, post-run verification, and an inspectable trace. It does not own a domain's business logic or ship a production tool catalog.

All harness modules live under `BeamAgent.*` (including `BeamAgent.LLM.*` and `BeamAgent.Tools.*`). Consumers provide an LLM client, tools map, and optional verifier to `BeamAgent.API.run/2`.

## Runtime topology

`BeamAgent.Application` starts a `BeamAgent.RunSupervisor` (`DynamicSupervisor`). Each API invocation starts an anonymous `BeamAgent.Runner` child with temporary restart semantics. Runs are isolated processes and can proceed concurrently; a finished, failed, or crashed run is terminal and is not automatically restarted.

`BeamAgent.API.run/2` starts the runner, monitors it, asks it to execute, and waits for a result. Runner crashes and hard timeouts are converted into `BeamAgent.Run` results. The API timeout is a backstop beyond the runner's cooperative execution-time guardrail; tool execution cannot be preempted by the guardrail while it is in flight.

## One run

1. `BeamAgent.State.new/1` initializes counters, context, and trace for a goal.
2. `BeamAgent.Runner` checks time/iteration guardrails, compresses context if needed, checks the final message count, and calls the configured `BeamAgent.LLM.Client` implementation.
3. A model reply finishes execution. A tool call is recorded in context and trace, checked against tool-call limits, and dispatched by `BeamAgent.Tools.Registry` through the per-run tools map. The result is correlated to the request by its call ID, recorded, and the run continues.
4. A natural completion is converted into a candidate `BeamAgent.Run` and passed to `BeamAgent.Verifier`. The default verifier checks execution completion, answer presence, and any required tools. A custom verifier can replace it.
5. Success or failure is returned as `{:ok, run}` / `{:error, run}`. The structured result carries status, error information, timing/counters, and the trace.

## Core invariants

- Goal and optional system prompt are retained in the model context. Only accumulated messages can be compressed; compression is deterministic and does not call the LLM.
- Tool-call requests and matching results retain the same call ID in the model history and execution trace.
- Guardrail failures, unknown tools, verifier failures, crashes, and hard timeouts remain distinguishable in the returned run.
- The append-only execution trace is part of the outcome on normal runner paths and records both successful and failed transitions.
- Domain-specific behavior is injected by consumers; do not add shopping/research/business logic to the core just because it is a useful example.

## Extension points

- LLM provider: implement `BeamAgent.LLM.Client` and pass `{module, opts}`.
- Tool: implement `BeamAgent.Tools.Behaviour` and register the module in the run's `:tools` map.
- Verification: implement `BeamAgent.Verifier.Behaviour` and pass it through `verification: [module: ...]`.
- Guardrails: extend the guardrail dispatcher and focused checks while preserving explicit error outcomes.

See the [README](../README.md) for the consumer-facing usage example and [glossary](glossary.md) for project terminology.
