defmodule BeamAgent.Tools.Echo do
  @moduledoc """
  A simple module for echoing values.
  """
  @behaviour BeamAgent.Tools.Behaviour

  @impl true
  @spec name() :: :echo
  def name, do: :echo

  @impl true
  @spec description() :: String.t()
  def description, do: "A simple tool that echoes back the input value."

  @impl true
  @spec execute(map()) :: {:ok, term()} | {:error, :invalid_input}
  def execute(%{"text" => text}) do
    {:ok, text}
  end

  def execute(%{text: text}) do
    {:ok, text}
  end

  def execute(_), do: {:error, :invalid_input}
end
