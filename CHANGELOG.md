# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-08-27

Initial release.

### Added

- `BeamAgent.API.run/2` — the public entry point: runs a goal to completion
  under supervision and returns `{:ok, run}` / `{:error, run}`.
- `BeamAgent.Runner` — the LLM-driven tool-use loop, as an isolated,
  supervised `GenServer` per run (`BeamAgent.RunSupervisor`), so any number
  of runs can execute concurrently and one crashing has no effect on the
  others.
- `BeamAgent.Context` — deterministic (no LLM call) context compression
  that keeps the model-facing message count bounded as a run goes on.
- `BeamAgent.Guardrails` — independently configurable `MaxIterations`,
  `MaxContextMessages`, `MaxExecutionTime`, and `MaxToolCalls` checks.
- `BeamAgent.Verifier` — pluggable post-run verification
  (`BeamAgent.Verifier.Behaviour`, with `BeamAgent.Verifier.Default`
  checking execution status, answer presence, and required tools) that
  catches a model claiming success without doing the work.
- `BeamAgent.LLM.Client` — the one-callback behaviour a real LLM provider
  implements to plug into a run.
- `BeamAgent.Tools.Behaviour` / `BeamAgent.Tools.Registry` — an injectable
  tool registry; each run supplies its own `tools` map rather than the
  harness shipping a hardcoded one.
- `BeamAgent.Run` / `BeamAgent.Trace` — the structured result and full,
  inspectable execution trace returned on every run, success or failure.
