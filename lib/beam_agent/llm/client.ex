defmodule BeamAgent.LLM.Client do
  @moduledoc """
  Behaviour implemented by every LLM provider.
  """

  @type message :: %{
          role: atom(),
          content: String.t()
        }

  @type tool_call :: %{
          id: String.t(),
          name: atom(),
          arguments: map()
        }

  @type response ::
          {:reply, String.t()}
          | {:tool_call, tool_call()}

  @callback chat([message()], keyword()) :: response()
end
