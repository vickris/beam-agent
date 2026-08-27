defmodule BeamAgent.LLM.Config do
  @moduledoc """
  Configuration for the LLM client.
  """

  @type t :: %__MODULE__{
          module: module(),
          options: keyword()
        }
  defstruct [
    :module,
    options: []
  ]
end
