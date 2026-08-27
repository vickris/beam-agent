defmodule BeamAgent.Verifier.Default do
  @moduledoc """
  Default verifier: checks that the run finished, produced an answer, and
  called every tool listed under `:required_tools`.
  """

  @behaviour BeamAgent.Verifier.Behaviour

  alias BeamAgent.Run

  @impl true
  def verify(%Run{} = run, opts \\ []) do
    required_tools = Keyword.get(opts, :required_tools, [])

    with :ok <- verify_execution(run),
         :ok <- verify_answer(run),
         :ok <- verify_required_tools(run.trace, required_tools) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_execution(%Run{execution_status: :finished}), do: :ok

  defp verify_execution(%Run{execution_status: status}) do
    {:error, {:invalid_execution_status, status}}
  end

  defp verify_answer(%Run{answer: answer}) when not is_nil(answer), do: :ok
  defp verify_answer(_run), do: {:error, :missing_answer}

  defp verify_required_tools(trace, required_tools) do
    executed_tools =
      trace
      |> Enum.filter(fn step -> step.type == :tool_completed end)
      |> Enum.map(fn step -> step.payload.tool end)

    missing_tools = required_tools -- executed_tools

    if missing_tools == [] do
      :ok
    else
      {:error, {:missing_required_tools, missing_tools}}
    end
  end
end
