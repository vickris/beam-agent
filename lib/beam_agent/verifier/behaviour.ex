defmodule BeamAgent.Verifier.Behaviour do
  @moduledoc """
  Behaviour implemented by every verifier.

  A verifier runs once, after the runner naturally reaches a reply, and
  decides whether the run actually satisfied its goal — turning a
  plausible-looking finish into a `verification_status: :failed` run when it
  didn't. Configure a custom implementation via the `:module` key in a run's
  `:verification` opts (see `BeamAgent.Verifier`); the default is
  `BeamAgent.Verifier.Default`.
  """

  @callback verify(run :: BeamAgent.Run.t(), opts :: keyword()) :: :ok | {:error, term()}
end
