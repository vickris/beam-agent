defmodule BeamAgent.RunSupervisor do
  @moduledoc """
  Dynamically supervises individual agent executions.

  A `DynamicSupervisor` (`strategy: :one_for_one`) started once under this
  application's supervisor. Every call to `start_run/1` adds one
  `BeamAgent.Runner` child with `restart: :temporary` — a run that finishes,
  fails, or crashes is simply gone; it is never automatically restarted,
  since a completed or crashed run is a terminal result to hand back to the
  caller, not a transient failure to retry. Because children are dynamic and
  independent, any number of runs can be active at once.
  """

  use DynamicSupervisor

  @doc false
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts one `BeamAgent.Runner` under this supervisor with `opts` (see
  `BeamAgent.Runner.start_link/1` for accepted keys). Returns `{:ok, pid}` on
  success, matching `DynamicSupervisor.start_child/2`.
  """
  @spec start_run(keyword()) :: DynamicSupervisor.on_start_child()
  def start_run(opts) do
    DynamicSupervisor.start_child(
      __MODULE__,
      {BeamAgent.Runner, opts}
    )
  end
end
