defmodule BeamAgent.Guardrails.Telemetry do
  @moduledoc false

  alias BeamAgent.State
  alias BeamAgent.Telemetry

  @doc """
  Observes a guardrail result at its consumption boundary without changing it.

  Only known rejections emit an event. Success and unrecognized results remain
  silent. State and raw reasons are used locally to select documented numeric
  measurements; neither is forwarded to handlers.
  """
  @spec observe(:ok | {:error, term()}, State.t(), keyword(), atom(), reference()) ::
          :ok | {:error, term()}
  def observe(:ok, _state, _opts, _phase, _run_id), do: :ok

  def observe({:error, reason} = result, state, opts, phase, run_id) do
    case rejection(reason, state, opts) do
      {guardrail, observed, limit, unit} ->
        Telemetry.point(
          [:guardrail, :rejected],
          %{observed: observed, limit: limit},
          %{
            run_id: run_id,
            iteration: state.iteration,
            guardrail: guardrail,
            phase: phase,
            unit: unit
          }
        )

      nil ->
        :ok
    end

    result
  end

  defp rejection(:max_iterations_reached, state, opts),
    do: {:max_iterations, state.iteration, Keyword.get(opts, :max_iterations, 5), :count}

  defp rejection(:max_tool_calls_reached, state, opts),
    do: {:max_tool_calls, state.tool_calls, Keyword.get(opts, :max_tool_calls, 5), :count}

  defp rejection(
         {:max_execution_time_reached, %{elapsed_ms: observed, maximum_ms: limit}},
         _state,
         _opts
       ),
       do: {:max_execution_time, observed, limit, :millisecond}

  defp rejection(
         {:max_context_messages_exceeded, %{actual: observed, maximum: limit}},
         _state,
         _opts
       ),
       do: {:max_context_messages, observed, limit, :count}

  defp rejection(_reason, _state, _opts), do: nil
end
