defmodule BeamAgent.RunSupervisor do
  @moduledoc """
  Dynamically supervises individual agent executions.
  """

  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_run(opts) do
    DynamicSupervisor.start_child(
      __MODULE__,
      {BeamAgent.Runner, opts}
    )
  end
end
