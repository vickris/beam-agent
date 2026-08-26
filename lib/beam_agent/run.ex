defmodule BeamAgent.Run do
  @moduledoc """
  Represents a completed outcome of a single agent execution.
  """
  @enforce_keys [
    :goal,
    :execution_status,
    :verification_status,
    :iterations,
    :tool_calls,
    :started_at,
    :finished_at,
    :duration_ms,
    :trace
  ]
  defstruct [
    :goal,
    :execution_status,
    :verification_status,
    :answer,
    :error,
    :iterations,
    :tool_calls,
    :started_at,
    :finished_at,
    :duration_ms,
    :trace,
    :verification_error
  ]

  def timeout(goal, timeout_ms) do
    now = DateTime.utc_now()

    %__MODULE__{
      goal: goal,
      execution_status: :failed,
      verification_status: :not_run,
      answer: nil,
      error: {:execution_timeout, timeout_ms},
      iterations: nil,
      tool_calls: nil,
      started_at: nil,
      finished_at: now,
      duration_ms: timeout_ms,
      trace: [],
      verification_error: nil
    }
  end

  def crash(goal, reason) do
    %__MODULE__{
      goal: goal,
      execution_status: :failed,
      verification_status: :not_run,
      answer: nil,
      error: {:runner_crashed, reason},
      iterations: nil,
      tool_calls: nil,
      started_at: nil,
      finished_at: DateTime.utc_now(),
      duration_ms: nil,
      trace: [],
      verification_error: nil
    }
  end
end
