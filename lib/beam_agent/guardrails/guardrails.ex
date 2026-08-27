defmodule BeamAgent.Guardrails do
  @moduledoc """
  Thin dispatcher over the individual guardrail checks, each its own module:
  `BeamAgent.Guardrails.MaxIterations`, `MaxContextMessages`,
  `MaxExecutionTime`, and `MaxToolCalls`. All read their options from the
  same `guardrails` keyword list passed to `BeamAgent.Runner.start_link/1`
  (via `BeamAgent.API.run/2`'s `:guardrails` opt) — there's no shared config
  struct, each check just looks up its own key with its own default.
  """

  alias BeamAgent.Guardrails.{
    MaxContextMessages,
    MaxIterations,
    MaxExecutionTime,
    MaxToolCalls
  }

  alias BeamAgent.State

  @doc "Time and iteration checks run before every step (`MaxExecutionTime`, `MaxIterations`)."
  @spec check_before_step(State.t(), keyword()) :: :ok | {:error, term()}
  def check_before_step(state, opts) do
    with :ok <- MaxExecutionTime.check(state, opts),
         :ok <- MaxIterations.check(state, opts) do
      :ok
    else
      error -> error
    end
  end

  @doc "Time, iteration, and tool-call checks run before every tool call (adds `MaxToolCalls`)."
  @spec check_before_tool(State.t(), keyword()) :: :ok | {:error, term()}
  def check_before_tool(state, opts) do
    with :ok <- MaxExecutionTime.check(state, opts),
         :ok <- MaxIterations.check(state, opts),
         :ok <- MaxToolCalls.check(state, opts) do
      :ok
    else
      error -> error
    end
  end

  @doc "Delegates to `MaxIterations.check/2`."
  @spec check_iterations(State.t(), keyword()) :: :ok | {:error, term()}
  def check_iterations(state, opts) do
    MaxIterations.check(state, opts)
  end

  @doc "Delegates to `MaxContextMessages.check/2`, run after context compression."
  @spec check_context(State.t(), keyword()) :: :ok | {:error, term()}
  def check_context(state, opts) do
    MaxContextMessages.check(state, opts)
  end
end
