defmodule BeamAgent.Telemetry do
  @moduledoc false

  # Internal emission boundary. Extend these allowlists only alongside a
  # documented event contract; never forward execution payloads or options.
  @measurement_keys [
    :system_time,
    :monotonic_time,
    :duration,
    :count,
    :iterations,
    :tool_calls,
    :before_count,
    :after_count,
    :compressed_messages,
    :summary_chars,
    :configured_max_messages,
    :minimum_messages,
    :observed,
    :limit
  ]
  @error_types [
    :startup_failed,
    :verification_failed,
    :execution_failed,
    :runner_crashed,
    :execution_timeout,
    :unknown_tool,
    :max_iterations_reached,
    :max_tool_calls_reached,
    :max_execution_time_reached,
    :max_context_messages_exceeded,
    :context_limit_too_small,
    :unexpected_result,
    :exception
  ]

  @doc """
  Emits an event beneath `[:beam_agent]` using only allowed fields and values.

  Correlation values must be opaque references. Measurements must be integers.
  Run classifications must belong to the finite allowlist for each field.
  Unknown fields and invalid values are omitted, including nested payloads.
  No runtime events are emitted unless this function is explicitly called.

  Handlers run synchronously; consumers must keep them fast. Telemetry handles
  catchable handler failures by detaching the failing handler.
  """
  @spec execute([atom()], map(), map()) :: :ok
  def execute(event, measurements, metadata) do
    :telemetry.execute(
      [:beam_agent | event],
      allow(measurements, @measurement_keys, &is_integer/1),
      Map.filter(metadata, &valid_metadata?/1)
    )
  end

  @doc "Emits a point event with native timestamps and count 1, applying the same allowlists."
  @spec point([atom()], map(), map()) :: :ok
  def point(event, measurements, metadata) do
    execute(
      event,
      Map.merge(measurements, %{
        system_time: System.system_time(),
        monotonic_time: System.monotonic_time(),
        count: 1
      }),
      metadata
    )
  end

  defp valid_metadata?({:run_id, value}), do: is_reference(value)
  defp valid_metadata?({:telemetry_span_context, value}), do: is_reference(value)
  defp valid_metadata?({:outcome, value}), do: value in [:ok, :error]
  defp valid_metadata?({:execution_status, value}), do: value in [:finished, :failed, :unknown]

  defp valid_metadata?({:verification_status, value}),
    do: value in [:passed, :failed, :not_run, :unknown]

  defp valid_metadata?({:error_type, value}), do: value in @error_types
  defp valid_metadata?({:kind, value}), do: value in [:error, :exit, :throw]
  defp valid_metadata?({:iteration, value}), do: is_integer(value) and value >= 0

  defp valid_metadata?({:guardrail, value}),
    do: value in [:max_iterations, :max_tool_calls, :max_context_messages, :max_execution_time]

  defp valid_metadata?({:phase, value}), do: value in [:before_step, :before_tool, :context]
  defp valid_metadata?({:unit, value}), do: value in [:count, :millisecond]
  defp valid_metadata?(_field), do: false

  defp allow(values, keys, valid?) do
    values
    |> Map.take(keys)
    |> Map.filter(fn {_key, value} -> valid?.(value) end)
  end
end
