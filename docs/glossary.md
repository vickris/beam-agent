# Glossary

- **Agent run** — One attempt to execute a goal, represented by a supervised `BeamAgent.Runner` process and returned as a `BeamAgent.Run`.
- **Runner** — An anonymous `GenServer` that owns one run's state and drives the model/tool cycle.
- **Run supervisor** — The `DynamicSupervisor` that starts and cleans up independent runner processes.
- **LLM client** — A module implementing `BeamAgent.LLM.Client`; translates model/provider interaction into a reply or tool-call result.
- **Tool** — A consumer-provided module implementing `BeamAgent.Tools.Behaviour`, available only when supplied in that run's tools map.
- **Tool call ID** — Provider-supplied identifier connecting an assistant tool-call request to its matching result and trace events.
- **Context** — Ordered messages sent to the model, including the goal, optional system prompt, optional history summary, and accumulated exchanges.
- **Context compression** — Deterministic folding of older accumulated messages into a bounded summary; it does not discard the goal or call the model.
- **Guardrail** — A configured limit/check that stops a run, such as maximum iterations, context messages, execution time, or tool calls.
- **Verification** — Post-execution checks that decide whether a completed run satisfies its expected conditions; distinct from execution status.
- **Trace** — Ordered `BeamAgent.Trace.Step` records describing run events, included in the returned run for inspection.
- **Execution status** — Whether the runner finished (`:finished`) or execution failed (`:failed`).
- **Verification status** — Whether post-run verification passed, failed, or was not run because execution did not finish.
- **Domain-specific consumer** — An application built on the harness that supplies its own goal logic, tools, provider client, and verification policy.
