defmodule BeamAgent.Telemetry do
  @moduledoc false

  # Internal emission boundary. Extend these allowlists only alongside a
  # documented event contract; never forward execution payloads or options.
  @measurement_keys [:system_time, :monotonic_time, :duration, :count, :iterations, :tool_calls]
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

  defp valid_metadata?({:run_id, value}), do: is_reference(value)
  defp valid_metadata?({:telemetry_span_context, value}), do: is_reference(value)
  defp valid_metadata?({:outcome, value}), do: value in [:ok, :error]
  defp valid_metadata?({:execution_status, value}), do: value in [:finished, :failed, :unknown]

  defp valid_metadata?({:verification_status, value}),
    do: value in [:passed, :failed, :not_run, :unknown]

  defp valid_metadata?({:error_type, value}), do: value in @error_types
  defp valid_metadata?({:kind, value}), do: value in [:error, :exit, :throw]
  defp valid_metadata?(_field), do: false

  defp allow(values, keys, valid?) do
    values
    |> Map.take(keys)
    |> Map.filter(fn {_key, value} -> valid?.(value) end)
  end
end
