defmodule BeamAgent.Tools.Crash do
  @moduledoc """
  A tool that always raises. Exists to exercise runner crash isolation —
  that a tool blowing up takes down only its own run, not the caller or any
  other concurrent run (see `BeamAgent.RunSupervisor`).
  """

  @behaviour BeamAgent.Tools.Behaviour

  @impl true
  @spec name() :: :crash
  def name, do: :crash

  @impl true
  @spec description() :: String.t()
  def description do
    "Crashes intentionally for supervision tests."
  end

  @impl true
  @spec execute(map()) :: no_return()
  def execute(_args) do
    raise "intentional tool crash"
  end
end
