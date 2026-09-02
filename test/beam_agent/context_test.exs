defmodule BeamAgent.ContextTest do
  use ExUnit.Case, async: true

  alias BeamAgent.Context
  alias BeamAgent.Tools.Echo

  test "pairs a tool call with its result by call id" do
    tool_call = %{id: "call-42", name: :echo, arguments: %{text: "hi"}}

    messages =
      Context.new("Do the thing")
      |> Context.add_tool_call(tool_call)
      |> Context.add_tool_result(tool_call.id, "hi")
      |> Context.messages()

    assert [
             %{role: :user, content: "Do the thing"},
             %{role: :assistant, type: :tool_call, call_id: "call-42", name: :echo},
             %{role: :tool, type: :tool_result, call_id: "call-42", content: "hi"}
           ] = messages
  end

  test "does not compress context within the limit" do
    context =
      Context.new("Complete the task")
      |> Context.add_tool_result("call-1", "first result")

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
      |> Context.add_tool_result("call-1", "result one")
      |> Context.add_tool_result("call-2", "result two")
      |> Context.add_tool_result("call-3", "result three")
      |> Context.add_tool_result("call-4", "result four")

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
      |> Context.add_tool_result("call-1", "one")
      |> Context.add_tool_result("call-2", "two")
      |> Context.add_tool_result("call-3", "three")
      |> Context.add_tool_result("call-4", "four")

    assert {:ok, context, _metadata} =
             Context.compress(
               context,
               max_messages: 4
             )

    context =
      Context.add_tool_result(
        context,
        "call-5",
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
      |> Context.add_tool_result("call-1", "result one")
      |> Context.add_tool_result("call-2", "result two")

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
