defmodule BeamAgent.Verifier do
  @moduledoc """
  Verifies whether an agent execution satisfied the expected conditions.

  This is a thin dispatcher: it runs whichever module is configured under
  the `:module` key of a run's `:verification` opts (defaulting to
  `BeamAgent.Verifier.Default`), so callers can plug in domain-specific
  verification — e.g. checking the answer's shape, calling out to another
  service, requiring specific tool arguments — by implementing
  `BeamAgent.Verifier.Behaviour` and passing `verification: [module: MyVerifier, ...]`.
  """

  alias BeamAgent.Run
  alias BeamAgent.Verifier.Default

  @doc """
  Runs the configured verifier (`opts[:module]`, default
  `BeamAgent.Verifier.Default`) against `run`.
  """
  @spec verify(Run.t(), keyword()) :: :ok | {:error, term()}
  def verify(%Run{} = run, opts \\ []) do
    module = Keyword.get(opts, :module, Default)
    module.verify(run, opts)
  end
end
