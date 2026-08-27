defmodule BeamAgent.Run do
  @moduledoc """
  Represents a completed outcome of a single agent execution.

  This is the struct `BeamAgent.API.run/2` hands back on every path — a
  normal finish, a failed guardrail, a hard timeout, or a runner crash — so
  callers always get one consistent shape with a full `trace` to inspect,
  rather than needing to handle each failure mode differently.
  """

  @typedoc """
  `:execution_status` reflects whether the runner itself finished
  (`:finished`) or not (`:failed`); `:verification_status` reflects the
  separate, subsequent check of whether the result actually satisfied the
  goal (`:passed`, `:failed`, or `:not_run` when execution never finished).
  """
  @type t :: %__MODULE__{
          goal: String.t(),
          execution_status: :finished | :failed,
          verification_status: :passed | :failed | :not_run,
          answer: term() | nil,
          error: term() | nil,
          iterations: non_neg_integer() | nil,
          tool_calls: non_neg_integer() | nil,
          started_at: DateTime.t() | nil,
          finished_at: DateTime.t(),
          duration_ms: non_neg_integer() | nil,
          trace: [BeamAgent.Trace.Step.t()],
          verification_error: term() | nil
        }

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

  @doc """
  Builds the `Run` returned when `BeamAgent.API.run/2`'s own hard timeout
  fires — the runner never replied within `timeout_ms` and was force
  -terminated. `error` is `{:execution_timeout, timeout_ms}`.
  """
  @spec timeout(String.t(), non_neg_integer()) :: t()
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

  @doc """
  Builds the `Run` returned when the runner process itself crashed (e.g. a
  tool raised) rather than reaching a normal finish or failure. `error` is
  `{:runner_crashed, reason}`, where `reason` is the process exit reason.
  """
  @spec crash(String.t(), term()) :: t()
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
