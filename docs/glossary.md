### Tool registry

The per-run map used to resolve a tool name to a tool implementation.

This is currently implemented by `BeamAgent.Tools.Registry`.

It is not an Elixir `Registry` process.

### Run registry

A future OTP Registry used to locate a running BeamAgent execution by its
run identifier.
