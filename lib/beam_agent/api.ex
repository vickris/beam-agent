defmodule BeamAgent.API do
  @moduledoc """
  Public API for executing agents.
  """

  # Extra time given to the runner beyond its own `:max_execution_time_ms`
  # guardrail before the API gives up on it. The guardrail is only checked
  # between steps/tool calls, so a run can overshoot it by roughly one
  # step's duration before the runner notices and replies on its own; this
  # grace period lets that graceful `:max_execution_time_reached` failure
  # win the race. The receive timeout below is a backstop for a runner
  # that is genuinely stuck, not the primary enforcement mechanism.
  @timeout_grace_ms 1_000

  def run(goal, opts) do
    timeout =
      opts
      |> Keyword.get(:guardrails, [])
      |> Keyword.get(:max_execution_time_ms, 30_000)

    opts = Keyword.put(opts, :goal, goal)

    with {:ok, pid} <-
           BeamAgent.RunSupervisor.start_run(opts) do
      monitor_ref = Process.monitor(pid)
      BeamAgent.Runner.run(pid, self())

      await_run(
        pid,
        monitor_ref,
        goal,
        timeout + @timeout_grace_ms
      )
    else
      {:error, reason} ->
        IO.puts("Could not start run due to this error: #{inspect(reason)}")
    end
  end

  defp await_run(
         pid,
         monitor_ref,
         goal,
         timeout
       ) do
    receive do
      {:agent_run_finished, ^pid, result} ->
        Process.demonitor(
          monitor_ref,
          [:flush]
        )

        result

      {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
        crash_result(
          goal,
          reason
        )
    after
      timeout ->
        timeout_result(
          pid,
          monitor_ref,
          goal,
          timeout
        )
    end
  end

  defp timeout_result(
         pid,
         monitor_ref,
         goal,
         timeout
       ) do
    terminate_runner(pid)

    receive do
      {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
        :ok
    after
      100 ->
        Process.demonitor(
          monitor_ref,
          [:flush]
        )
    end

    {:error,
     BeamAgent.Run.timeout(
       goal,
       timeout
     )}
  end

  defp terminate_runner(pid) do
    case DynamicSupervisor.terminate_child(
           BeamAgent.RunSupervisor,
           pid
         ) do
      :ok ->
        :ok

      {:error, :not_found} ->
        :ok
    end
  end

  defp crash_result(goal, reason) do
    {:error,
     BeamAgent.Run.crash(
       goal,
       reason
     )}
  end
end
