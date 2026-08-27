defmodule BeamAgent.Tools.Registry do
  @moduledoc """
  Dispatches a tool call to the module registered for it.

  The registry itself holds no tools — callers pass a `tools` map
  (`%{atom() => module}`, each module implementing `BeamAgent.Tools.Behaviour`)
  through `BeamAgent.API.run/2`'s `:tools` option, and it flows down to every
  call here. This keeps the harness domain-agnostic: it ships no built-in
  tools of its own, only the dispatch mechanism.
  """

  @type tools :: %{optional(atom()) => module()}

  @doc """
  Looks up `tool_name` in `tools` and executes it with `args`.

  Returns `{:error, :unknown_tool}` if `tool_name` isn't a key in `tools`.
  """
  @spec call(tools(), atom(), map()) :: {:ok, term()} | {:error, term()}
  def call(tools, tool_name, args) when is_map(tools) do
    case Map.fetch(tools, tool_name) do
      {:ok, module} ->
        module.execute(args)

      :error ->
        {:error, :unknown_tool}
    end
  end
end
