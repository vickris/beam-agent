defmodule BeamAgent.LLM.Client do
  @moduledoc """
  Behaviour implemented by every LLM provider.
  """

  @type message :: %{
          role: atom(),
          content: String.t()
        }

  @type response ::
          {:reply, String.t()}
          | {:tool_call, atom(), map()}

  @callback chat([message()], keyword()) :: response()
end
