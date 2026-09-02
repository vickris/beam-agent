# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

BeamAgent is a general-purpose Elixir agent harness (not tied to any one agent's domain — `lib/shopping/` is a placeholder for a shopping/deal-finding layer built on top of it and is currently empty; the harness itself is equally suited to a research agent, a coding agent, a workflow agent, or an internal-automation agent). The framework runs an LLM-driven tool-use loop as an OTP `GenServer` supervised for concurrent runs, with deterministic context compression, iteration/context/time/tool-call guardrails, and post-run verification, and it exposes a full execution trace. It has no dependencies (`mix.exs` deps list is empty) — everything is built on stdlib/OTP. Everything lives under one `BeamAgent.*` namespace (including `BeamAgent.LLM.*` and `BeamAgent.Tools.*` — no bare `LLM`/`Tools` modules) so nothing generic collides with a consumer's own code or other hex packages; the top-level name itself avoids colliding with Elixir's stdlib `Agent` module.

Elixir was chosen for the BEAM properties: each agent run is an isolated process (one crash doesn't affect others), OTP supervision gives automatic restarts of the *supervisors themselves*, and message passing keeps tool execution clean.

## Commands

```bash
mix deps.get           # fetch deps (currently none declared)
mix compile             # compile
mix test                 # run the full test suite
mix test test/beam_agent/context_test.exs        # run one test file
mix test test/beam_agent/context_test.exs:21     # run a single test by line number
mix format                # format per .formatter.exs
```

The public entry point is `BeamAgent.API.run/2` — `BeamAgent.API.run(goal, llm: {module, opts}, tools: %{...}, verification: [...], guardrails: [...])` — which starts a run under supervision and blocks until it finishes, times out, or the runner process crashes (see tests below for the calling convention).

## Architecture

### Public API (`BeamAgent.API`, `lib/beam_agent/api.ex`)

`run/2` starts a run via `BeamAgent.RunSupervisor.start_run/1`, casts `BeamAgent.Runner.run/2`, then blocks in a `receive` for `{:agent_run_finished, pid, result}`. It layers its own timeout on top of the runner's own `:max_execution_time_ms` guardrail: since that guardrail is only checked between steps/tool calls, a run can overshoot it by roughly one step's duration, so the API adds a `@timeout_grace_ms` grace period before it gives up and force-terminates the runner itself. A runner crash (e.g. a tool raising) is caught via `Process.monitor/1` and turned into `BeamAgent.Run.crash/2` rather than taking down the caller.

### Supervision (`BeamAgent.RunSupervisor`, `lib/beam_agent/run_supervisor.ex`)

A `DynamicSupervisor` (`strategy: :one_for_one`) started once under `BeamAgent.Application`. Each call to `start_run/1` starts a new, independent `BeamAgent.Runner` child with `restart: :temporary` — a finished/failed/crashed run is a terminal result, never auto-restarted. **Multiple runs can be active concurrently**, each in its own isolated process; one crashing does not affect the others (`test/beam_agent/concurrency_test.exs` exercises this directly).

### The run loop (`BeamAgent.Runner`, `lib/beam_agent/runner.ex`)

A `GenServer` (started anonymously, not name-registered, so many can run at once). `start_link/1` takes `:goal` and `:llm` (required, `{module, opts}` tuple satisfying `BeamAgent.LLM.Client`), `:tools` (`%{atom() => module}`, defaults to `%{}` — see Tools below), plus `:verification` and `:guardrails` opts. `run/2` is an async `GenServer.cast` that drives the goal to completion and sends `{:agent_run_finished, self(), result}` back to the caller.

Execution is recursive, not literally looped: `step/4` → `run_checks/4` → `call_llm/4` → (on `{:tool_call, ...}`) `run_tool/6` → `execute_tool/6` → back into `step/4`. Each cycle:

1. `Guardrails.check_before_step/2` — `MaxExecutionTime` then `MaxIterations`.
2. `prepare_context/2` — calls `BeamAgent.Context.compress/2`; if compression still can't fit under the limit it fails with `:context_limit_too_small`.
3. `Guardrails.check_context/2` (`MaxContextMessages`) — a second check on the *final* message count actually sent to the model.
4. Iteration increments, a `:model_call` trace step is recorded, then the configured LLM module's `chat/2` is invoked.
5. The LLM returns either `{:reply, text}` (run finishes) or `{:tool_call, %{id, name, arguments}}` — the assistant tool-call message is appended to context, then the call is dispatched through `BeamAgent.Tools.Registry.call(tools, name, arguments)` after `Guardrails.check_before_tool/2` (adds `MaxToolCalls` on top of the before-step checks), the result is appended to context as a tool-result message tagged with the same call id, loop repeats.

Every state transition is recorded via `BeamAgent.State.trace/3` into an append-only `BeamAgent.Trace.Step` list — this is the audit trail included on `BeamAgent.Run.trace` on both success and failure paths, not just an internal debug log. Once the loop reaches a reply or a failure, `build_verified_run/2` builds a `BeamAgent.Run` via `BeamAgent.Run.Builder` and runs `BeamAgent.Verifier`; the final `{:ok, run}` / `{:error, run}` distinction is based on `run.execution_status` and `run.verification_status`, not just whether the LLM replied.

### Context and compression (`BeamAgent.Context`)

`BeamAgent.Context` owns exactly what gets sent to the model. The goal and (optional) system prompt are **never** dropped; only the accumulated `messages` list (tool results, assistant replies) is subject to compression. `compress/2` is deterministic (no LLM call): once the rendered message count exceeds `:max_context_messages`, the oldest messages are folded into a single running `summary` string (capped at `:summary_char_limit`, oldest content trimmed first) and replaced by one `:system` message. This repeats across iterations — the summary keeps absorbing newly-aged-out messages rather than resetting. `compress/2` is a guardrail-facing function; it errors with `:context_limit_too_small` if the configured max is too small to hold the fixed messages (goal + optional system prompt + at least one summary/message slot).

### Guardrails (`BeamAgent.Guardrails`, `lib/beam_agent/guardrails/`)

`BeamAgent.Guardrails` is a thin dispatcher over four independent checks, each its own module: `MaxIterations` (`state.iteration >= max`, default 5), `MaxContextMessages` (rendered message count vs. max, default 8), `MaxExecutionTime` (wall-clock elapsed vs. `:max_execution_time_ms`, default 30_000), and `MaxToolCalls` (`state.tool_calls >= max`, default 5). All read options from the same `guardrails` keyword list passed to `BeamAgent.Runner.start_link/1`; there's no shared config struct. `check_before_step/2` runs time+iterations; `check_before_tool/2` adds tool-calls on top.

### Verification (`BeamAgent.Verifier`, `lib/beam_agent/verifier/`)

`BeamAgent.Verifier.verify/2` is a thin dispatcher: it runs whichever module is configured under `verification[:module]` (default `BeamAgent.Verifier.Default`), so verification is pluggable per run rather than hardcoded. `BeamAgent.Verifier.Behaviour` defines the one-callback contract (`verify(run, opts) :: :ok | {:error, term()}`). `BeamAgent.Verifier.Default` is the built-in implementation: runs once, after the loop naturally reaches a `{:reply, ...}`, before the run is handed back to the caller — it's what turns a plausible-looking success into a `verification_status: :failed` run when the run didn't actually do what was asked. It checks: `execution_status == :finished`, `answer` is non-nil, and every tool in `:required_tools` actually appears as a `:tool_completed` trace step. This is the mechanism that catches an LLM hallucinating a success message without calling the tools it claimed to (`BeamAgent.LLM.Mock`'s `:hallucinate_success` mode exists specifically to exercise this).

### Run outcome (`BeamAgent.Run`, `BeamAgent.Run.Builder`)

`BeamAgent.Run` is the struct handed back from `BeamAgent.API.run/2` — goal, execution/verification status, answer, error, iterations, tool_calls, timestamps, duration, and the full trace. `BeamAgent.Run.Builder` constructs one from a `BeamAgent.State` (`success/1`, `verification_failed/2`, `execution_failed/2`); `BeamAgent.Run` itself also has `timeout/2` and `crash/2` constructors used directly by `BeamAgent.API` for the two failure paths that never reach the runner's own build step.

### LLM boundary (`BeamAgent.LLM.*`, `lib/beam_agent/llm/`)

`BeamAgent.LLM.Client` is a one-callback behaviour: `chat([message], opts) :: {:reply, text} | {:tool_call, %{id: String.t(), name: atom(), arguments: map()}}`. The `id` is the provider's identifier for that specific tool call (real APIs require it to correlate the tool result back to the call); `BeamAgent.LLM.Mock` just generates a unique `"mock-call-N"` string. `BeamAgent.Runner` threads it into the `:tool_requested` / `:tool_started` / `:tool_completed` / `:tool_failed` trace payloads as `tool_call_id`, and — for the model-facing history — records **two** context messages per tool round: `BeamAgent.Context.add_tool_call/2` appends the assistant's `type: :tool_call` message (carrying `call_id`, `name`, `arguments`) before the tool runs, then `add_tool_result/3` appends the `type: :tool_result` message tagged with the same `call_id`. Both are subject to compression like any other accumulated message. `BeamAgent.LLM.Mock` is the only implementation and is what the test suite runs against, selected via `mode:` in opts (`:normal`, `:loop_forever` — used to exercise the iteration guardrail, `:slow_loop` — used to exercise the execution-time guardrail, `:hallucinate_success`, `:unknown_tool`, `:crash_tool` — used to exercise runner-crash isolation). `BeamAgent.LLM.Config` is a scaffolded `{module, options}` struct not yet referenced anywhere — a real provider client would implement `BeamAgent.LLM.Client` and be passed to `BeamAgent.Runner` as `{module, opts}` the same way the mock is.

### Tools (`BeamAgent.Tools.*`, `lib/beam_agent/tools/`)

`BeamAgent.Tools.Behaviour` requires `name/0`, `description/0`, `execute/1`. `BeamAgent.Tools.Registry.call/3` is a stateless dispatcher — `call(tools, tool_name, args)` — over whatever `tools` map (`%{atom() => module}`) the caller passes to `BeamAgent.API.run/2`'s `:tools` opt; the harness ships **no built-in tools of its own**, only three reference/test implementations (`Echo`, `Sleep`, `Crash`) used by the test suite. An unknown tool name (or a `tools` map that doesn't include it) surfaces as `{:error, :unknown_tool}`, which `BeamAgent.Runner` turns into a failed run with a `:tool_failed` trace step (this is also how a hallucinated/unknown tool call from the model gets caught, separately from `BeamAgent.Verifier`'s required-tools check).

There is no `Handlers.*` layer — a shopping-domain `SaveComparison` tool/handler pair used to live in `lib/tools/` and `lib/handlers/` but was dead code (never registered) and has been removed; that kind of domain-specific tool belongs in `lib/shopping/`, built against `BeamAgent.Tools.Behaviour` like any other consumer of the harness, not inside it.
