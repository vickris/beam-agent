defmodule BeamAgent.Tools.Behaviour do
  @moduledoc """
  Behaviour implemented by every tool the agent can execute.
  """

  @callback name() :: atom()
  @callback description() :: String.t()

  @callback execute(map()) :: {:ok, term()} | {:error, term()}
end
