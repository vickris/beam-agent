defmodule BeamAgent.Telemetry do
  @moduledoc false

  # Internal emission boundary. Extend these allowlists only alongside a
  # documented event contract; never forward execution payloads or options.
  @metadata_keys [:run_id, :telemetry_span_context]
  @measurement_keys [:system_time, :monotonic_time, :duration, :count]

  @doc """
  Emits an event beneath `[:beam_agent]` using only allowed fields and values.

  Correlation values must be opaque references. Measurements must be integers.
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
      allow(metadata, @metadata_keys, &is_reference/1)
    )
  end

  defp allow(values, keys, valid?) do
    values
    |> Map.take(keys)
    |> Map.filter(fn {_key, value} -> valid?.(value) end)
  end
end
