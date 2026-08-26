defmodule BeamAgent.Context do
  @moduledoc """
  Owns the information sent to the model.

  Older messages may be deterministically compressed, but the original
  goal and optional system prompt are always preserved.
  """

  @default_summary_char_limit 1_000
  @summary_line_limit 200

  defstruct [
    :goal,
    :system_prompt,
    :summary,
    messages: []
  ]

  def new(goal, opts \\ []) when is_binary(goal) do
    %__MODULE__{
      goal: goal,
      system_prompt: Keyword.get(opts, :system_prompt),
      summary: nil,
      messages: []
    }
  end

  def messages(%__MODULE__{} = context) do
    []
    |> maybe_add_system_prompt(context.system_prompt)
    |> Kernel.++([message(:user, context.goal)])
    |> maybe_add_summary(context.summary)
    |> Kernel.++(context.messages)
  end

  def add_user_message(%__MODULE__{} = context, content) do
    append(context, :user, content)
  end

  def add_assistant_message(%__MODULE__{} = context, content) do
    append(context, :assistant, content)
  end

  def add_tool_result(%__MODULE__{} = context, result) do
    append(context, :tool, result)
  end

  def compress(%__MODULE__{} = context, opts) do
    max_messages = Keyword.fetch!(opts, :max_messages)

    summary_char_limit =
      Keyword.get(
        opts,
        :summary_char_limit,
        @default_summary_char_limit
      )

    before_count = length(messages(context))

    cond do
      before_count <= max_messages ->
        {:ok, context,
         %{
           compressed?: false,
           before_count: before_count,
           after_count: before_count,
           compressed_messages: 0
         }}

      true ->
        compress_messages(
          context,
          max_messages,
          summary_char_limit,
          before_count
        )
    end
  end

  defp compress_messages(
         context,
         max_messages,
         summary_char_limit,
         before_count
       ) do
    fixed_message_count =
      1 +
        system_prompt_count(context.system_prompt) +
        1

    recent_capacity = max_messages - fixed_message_count

    if recent_capacity < 1 do
      {:error,
       {:context_limit_too_small,
        %{
          configured: max_messages,
          minimum: fixed_message_count + 1
        }}}
    else
      compress_older_messages(
        context,
        recent_capacity,
        summary_char_limit,
        before_count
      )
    end
  end

  defp compress_older_messages(
         context,
         recent_capacity,
         summary_char_limit,
         before_count
       ) do
    overflow_count =
      max(length(context.messages) - recent_capacity, 0)

    {older_messages, recent_messages} =
      Enum.split(context.messages, overflow_count)

    summary =
      merge_summary(
        context.summary,
        older_messages,
        summary_char_limit
      )

    compressed_context = %{
      context
      | summary: summary,
        messages: recent_messages
    }

    {:ok, compressed_context,
     %{
       compressed?: true,
       before_count: before_count,
       after_count: length(messages(compressed_context)),
       compressed_messages: length(older_messages),
       summary_chars: String.length(summary)
     }}
  end

  defp append(context, role, content) do
    new_message = message(role, normalize_content(content))

    %{
      context
      | messages: context.messages ++ [new_message]
    }
  end

  defp message(role, content) do
    %{
      role: role,
      content: content
    }
  end

  defp merge_summary(existing_summary, older_messages, char_limit) do
    new_lines =
      Enum.map(
        older_messages,
        &summarize_message/1
      )

    [existing_summary | new_lines]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n")
    |> limit_summary(char_limit)
  end

  defp summarize_message(message) do
    role = Map.get(message, :role, :unknown)

    content =
      message
      |> Map.get(:content)
      |> normalize_content()
      |> truncate(@summary_line_limit)

    "#{role}: #{content}"
  end

  defp normalize_content(content) when is_binary(content), do: content

  defp normalize_content(content) do
    inspect(
      content,
      limit: 50,
      printable_limit: 500
    )
  end

  defp truncate(content, limit) do
    if String.length(content) <= limit do
      content
    else
      String.slice(content, 0, limit) <> "…"
    end
  end

  defp limit_summary(summary, limit) do
    if String.length(summary) <= limit do
      summary
    else
      prefix = "[older compressed history omitted]\n"
      remaining = max(limit - String.length(prefix), 0)

      prefix <>
        String.slice(
          summary,
          -remaining,
          remaining
        )
    end
  end

  defp maybe_add_system_prompt(messages, nil), do: messages
  defp maybe_add_system_prompt(messages, ""), do: messages

  defp maybe_add_system_prompt(messages, prompt) do
    messages ++ [message(:system, prompt)]
  end

  defp maybe_add_summary(messages, nil), do: messages
  defp maybe_add_summary(messages, ""), do: messages

  defp maybe_add_summary(messages, summary) do
    messages ++
      [
        message(
          :system,
          "Compressed execution history:\n#{summary}"
        )
      ]
  end

  defp system_prompt_count(nil), do: 0
  defp system_prompt_count(""), do: 0
  defp system_prompt_count(_prompt), do: 1

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
