defmodule BeamAgent do
  @moduledoc """
  BeamAgent is a general-purpose Elixir agent harness: an LLM-driven
  tool-use loop, deterministic context compression, guardrails, and
  post-run verification, built as OTP processes so each run is isolated —
  one crashing has no effect on any other — and supervised for automatic
  cleanup.

  This module is documentation only; `BeamAgent.API.run/2` is the entry
  point.

  ## Quick example

      BeamAgent.API.run(
        "Say hello",
        llm: {MyApp.LLMClient, model: "..."},
        tools: %{echo: MyApp.Tools.Echo},
        guardrails: [max_iterations: 5],
        verification: [required_tools: [:echo]]
      )
      #=> {:ok, %BeamAgent.Run{}} | {:error, %BeamAgent.Run{}}

  To plug in a real model and tools, implement `BeamAgent.LLM.Client` and
  `BeamAgent.Tools.Behaviour` respectively — both are one-callback-ish
  behaviours designed to be easy to satisfy. `BeamAgent.Run` is what you get
  back either way: goal, status, answer, the full execution `trace`, and
  timestamps.
  """
end
