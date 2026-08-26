defmodule BeamAgent.Guardrails.MaxContextMessages do
  @moduledoc """
  Ensures that the final model-facing context is within its configured
  message limit.
  """

  alias BeamAgent.Context

  def check(state, opts) do
    maximum =
      Keyword.get(
        opts,
        :max_context_messages,
        8
      )

    actual =
      state.context
      |> Context.messages()
      |> length()

    if actual <= maximum do
      :ok
    else
      {:error,
       {:max_context_messages_exceeded,
        %{
          actual: actual,
          maximum: maximum
        }}}
    end
  end
end
