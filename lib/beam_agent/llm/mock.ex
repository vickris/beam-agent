defmodule BeamAgent.LLM.Mock do
  @moduledoc """
  Deterministic LLM implementation used to exercise the agent harness.
  """

  @behaviour BeamAgent.LLM.Client

  @impl true
  def chat(messages, opts) do
    mode = Keyword.get(opts, :mode, :normal)

    case mode do
      :normal ->
        normal(messages)

      :slow_loop ->
        slow_loop(messages, opts)

      :loop_forever ->
        loop_forever(messages)

      :hallucinate_success ->
        hallucinate_success()

      :unknown_tool ->
        unknown_tool()

      :crash_tool ->
        {:tool_call, :crash, %{}}

      mode ->
        raise ArgumentError, "unsupported mock LLM mode: #{inspect(mode)}"
    end
  end

  defp slow_loop(_messages, opts) do
    milliseconds =
      Keyword.get(
        opts,
        :sleep_ms,
        20
      )

    {:tool_call, :sleep, %{milliseconds: milliseconds}}
  end

  defp normal(messages) do
    case List.last(messages) do
      %{role: :user, content: content} ->
        {:tool_call, :echo, %{text: content}}

      %{role: :tool} ->
        {:reply, "Done!"}

      _message ->
        {:reply, "I am confused."}
    end
  end

  defp loop_forever(messages) do
    text =
      case List.last(messages) do
        %{content: content} when is_binary(content) -> content
        _message -> "Repeat"
      end

    {:tool_call, :echo, %{text: text}}
  end

  defp hallucinate_success() do
    {:reply, "I successfully compared every supermarket."}
  end

  defp unknown_tool() do
    {:tool_call, :delete_everything, %{}}
  end
end
