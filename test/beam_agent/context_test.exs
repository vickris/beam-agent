defmodule BeamAgent.ContextTest do
  use ExUnit.Case, async: true

  alias BeamAgent.Context
  alias BeamAgent.Tools.Echo

  test "does not compress context within the limit" do
    context =
      Context.new("Complete the task")
      |> Context.add_tool_result("first result")

    assert {:ok, unchanged, metadata} =
             Context.compress(
               context,
               max_messages: 4
             )

    assert unchanged == context
    refute metadata.compressed?
  end

  test "preserves the goal and recent messages" do
    context =
      Context.new("Find the cheapest store")
      |> Context.add_tool_result("result one")
      |> Context.add_tool_result("result two")
      |> Context.add_tool_result("result three")
      |> Context.add_tool_result("result four")

    assert {:ok, compressed, metadata} =
             Context.compress(
               context,
               max_messages: 4,
               summary_char_limit: 500
             )

    messages = Context.messages(compressed)

    assert length(messages) == 4
    assert metadata.compressed?
    assert metadata.compressed_messages == 2

    assert hd(messages) == %{
             role: :user,
             content: "Find the cheapest store"
           }

    assert Enum.at(messages, 1).role == :system
    assert Enum.at(messages, 2).content == "result three"
    assert Enum.at(messages, 3).content == "result four"
  end

  test "keeps context bounded after repeated compression" do
    context =
      Context.new("Keep working")
      |> Context.add_tool_result("one")
      |> Context.add_tool_result("two")
      |> Context.add_tool_result("three")
      |> Context.add_tool_result("four")

    assert {:ok, context, _metadata} =
             Context.compress(
               context,
               max_messages: 4
             )

    context =
      Context.add_tool_result(
        context,
        "five"
      )

    assert {:ok, context, metadata} =
             Context.compress(
               context,
               max_messages: 4
             )

    assert metadata.compressed?
    assert length(Context.messages(context)) <= 4
    assert List.last(Context.messages(context)).content == "five"
  end

  test "rejects an unusably small limit" do
    context =
      Context.new("Complete the task")
      |> Context.add_tool_result("result one")
      |> Context.add_tool_result("result two")

    assert {:error, {:context_limit_too_small, details}} =
             Context.compress(
               context,
               max_messages: 2
             )

    assert details.configured == 2
  end

  test "compresses context during a long run" do
    assert {:error, run} =
             BeamAgent.API.run(
               "Keep repeating",
               llm: {
                 BeamAgent.LLM.Mock,
                 mode: :loop_forever
               },
               tools: %{echo: Echo},
               guardrails: [
                 max_iterations: 6,
                 max_context_messages: 4,
                 summary_char_limit: 300
               ],
               verification: [
                 required_tools: [:echo]
               ]
             )

    assert Enum.any?(
             run.trace,
             &(&1.type == :context_compressed)
           )
  end
end
