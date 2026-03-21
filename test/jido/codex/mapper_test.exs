defmodule Jido.Codex.MapperTest do
  use ExUnit.Case, async: true

  alias Jido.Codex.Mapper
  alias Jido.Codex.Test.Fixtures

  test "maps session start events" do
    assert {:ok, [event]} = Mapper.map_event(Fixtures.thread_started(), [])
    assert event.type == :session_started
    assert event.provider == :codex
    assert event.session_id == "session-abc"

    assert {:ok, [configured]} = Mapper.map_event(Fixtures.session_configured(), [])
    assert configured.type == :session_started

    assert {:ok, [continuation]} = Mapper.map_event(Fixtures.turn_continuation(), [])
    assert continuation.type == :codex_turn_continuation
    assert continuation.payload["continuation_token"] == "ctok"
  end

  test "maps text delta and final events" do
    assert {:ok, [delta]} = Mapper.map_event(Fixtures.item_agent_message_delta(), [])
    assert delta.type == :output_text_delta
    assert delta.payload["text"] == "hello"

    assert {:ok, []} =
             Mapper.map_event(%Codex.Events.ItemAgentMessageDelta{thread_id: "session-abc", item: %{}}, [])

    assert {:ok, []} =
             Mapper.map_event(%Codex.Events.ItemAgentMessageDelta{thread_id: "session-abc", item: :not_a_map}, [])

    assert {:ok, [final]} = Mapper.map_event(Fixtures.item_completed_agent_message(), [])
    assert final.type == :output_text_final
    assert final.payload["text"] == "final"
  end

  test "maps thinking events" do
    assert {:ok, [delta]} = Mapper.map_event(Fixtures.reasoning_delta(), [])
    assert delta.type == :thinking_delta

    assert {:ok, [completed]} = Mapper.map_event(Fixtures.item_completed_reasoning(), [])
    assert completed.type == :thinking_delta
  end

  test "maps tool events" do
    assert {:ok, [call]} = Mapper.map_event(Fixtures.tool_call_requested(), [])
    assert call.type == :tool_call
    assert call.payload["name"] == "Read"

    assert {:ok, [result]} = Mapper.map_event(Fixtures.tool_call_completed(), [])
    assert result.type == :tool_result
    assert result.payload["is_error"] == false
  end

  test "maps file changes and usage" do
    assert {:ok, [file_change]} = Mapper.map_event(Fixtures.item_completed_file_change(), [])
    assert file_change.type == :file_change

    assert {:ok, [usage]} = Mapper.map_event(Fixtures.usage_updated(), [])
    assert usage.type == :codex_token_update
  end

  test "maps extended codex events" do
    assert {:ok, [rate]} = Mapper.map_event(Fixtures.rate_limits_updated(), [])
    assert rate.type == :codex_rate_limits_updated

    assert {:ok, [diff]} = Mapper.map_event(Fixtures.turn_diff_updated(), [])
    assert diff.type == :codex_turn_diff_updated

    assert {:ok, [plan]} = Mapper.map_event(Fixtures.turn_plan_updated(), [])
    assert plan.type == :codex_turn_plan_updated

    assert {:ok, [mcp]} = Mapper.map_event(Fixtures.mcp_tool_progress(), [])
    assert mcp.type == :codex_mcp_tool_progress

    assert {:ok, [rui]} = Mapper.map_event(Fixtures.request_user_input(), [])
    assert rui.type == :codex_request_user_input
  end

  test "maps warnings and terminal states" do
    assert {:ok, [warn]} = Mapper.map_event(Fixtures.config_warning(), [])
    assert warn.type == :codex_warning

    assert {:ok, [warn2]} = Mapper.map_event(Fixtures.warning(), [])
    assert warn2.type == :codex_warning

    assert {:ok, [usage, complete]} = Mapper.map_event(Fixtures.turn_completed(), [])
    assert usage.type == :usage
    assert complete.type == :session_completed

    assert {:ok, [failed]} = Mapper.map_event(Fixtures.turn_failed(), [])
    assert failed.type == :session_failed

    assert {:ok, [failed2]} = Mapper.map_event(Fixtures.error_event(), [])
    assert failed2.type == :session_failed

    assert {:ok, [cancelled]} = Mapper.map_event(Fixtures.turn_aborted(), [])
    assert cancelled.type == :session_cancelled
  end

  test "maps stream wrapper events" do
    run_item = Fixtures.run_item(Fixtures.turn_started())
    assert {:ok, [event]} = Mapper.map_event(run_item, [])
    assert event.type == :codex_turn_started

    {:ok, [raw_1, raw_2, raw_3]} =
      Mapper.map_event(
        %Codex.StreamEvent.RawResponses{events: [Fixtures.turn_started(), Fixtures.turn_completed()]},
        []
      )

    assert raw_1.type == :codex_turn_started
    assert raw_2.type == :usage
    assert raw_2.payload["input_tokens"] == 1
    assert raw_3.type == :session_completed

    assert {:ok, [agent_updated]} =
             Mapper.map_event(%Codex.StreamEvent.AgentUpdated{agent: nil, run_config: nil}, [])

    assert agent_updated.type == :codex_event

    assert {:ok, [guardrail]} =
             Mapper.map_event(
               %Codex.StreamEvent.GuardrailResult{
                 stage: :input,
                 guardrail: "policy",
                 result: :ok,
                 message: "safe"
               },
               []
             )

    assert guardrail.type == :codex_event

    assert {:ok, [tool_approval]} =
             Mapper.map_event(
               %Codex.StreamEvent.ToolApproval{
                 tool_name: "Read",
                 call_id: "call-1",
                 decision: :allow,
                 reason: "ok"
               },
               []
             )

    assert tool_approval.type == :codex_event
  end

  test "falls back to codex_event for unknown events" do
    assert {:ok, [event]} = Mapper.map_event(Fixtures.unknown_event(), [])
    assert event.type == :codex_event
    assert event.payload["event_module"] =~ "ContextCompacted"
  end

  test "falls back safely for unknown non-map events" do
    assert {:ok, [event]} = Mapper.map_event(:unknown_event, [])
    assert event.type == :codex_event
    assert event.payload["event_type"] == "unknown"
    assert event.payload["event_module"] == "unknown"
    assert event.session_id == nil
  end
end
