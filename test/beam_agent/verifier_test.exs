defmodule BeamAgent.VerifierTest do
  use ExUnit.Case, async: true

  alias BeamAgent.Tools.Echo
  alias BeamAgent.Verifier

  defmodule AlwaysFail do
    @moduledoc false
    @behaviour BeamAgent.Verifier.Behaviour

    @impl true
    def verify(_run, _opts), do: {:error, :custom_verifier_rejected}
  end

  defmodule AlwaysPass do
    @moduledoc false
    @behaviour BeamAgent.Verifier.Behaviour

    @impl true
    def verify(_run, _opts), do: :ok
  end

  test "defaults to BeamAgent.Verifier.Default when no :module is configured" do
    assert Verifier.verify(passing_run(), required_tools: [:echo]) == :ok

    assert Verifier.verify(passing_run(), required_tools: [:missing]) ==
             {:error, {:missing_required_tools, [:missing]}}
  end

  test "a custom verifier module can reject a run the default would have passed" do
    assert {:error, run} =
             BeamAgent.API.run(
               "Hello",
               llm: {BeamAgent.LLM.Mock, mode: :normal},
               tools: %{echo: Echo},
               verification: [module: AlwaysFail, required_tools: [:echo]]
             )

    assert run.verification_status == :failed
    assert run.verification_error == :custom_verifier_rejected
  end

  test "a custom verifier module can pass a run the default would have failed" do
    assert {:ok, run} =
             BeamAgent.API.run(
               "Complete the task",
               llm: {BeamAgent.LLM.Mock, mode: :hallucinate_success},
               verification: [module: AlwaysPass, required_tools: [:echo]]
             )

    assert run.verification_status == :passed
  end

  defp passing_run do
    %BeamAgent.Run{
      goal: "goal",
      execution_status: :finished,
      verification_status: :not_run,
      answer: "done",
      iterations: 1,
      tool_calls: 1,
      started_at: DateTime.utc_now(),
      finished_at: DateTime.utc_now(),
      duration_ms: 0,
      trace: [
        %BeamAgent.Trace.Step{
          iteration: 0,
          type: :tool_completed,
          timestamp: DateTime.utc_now(),
          payload: %{tool: :echo}
        }
      ]
    }
  end
end
