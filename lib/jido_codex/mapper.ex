defmodule Jido.Codex.Mapper do
  @moduledoc """
  Maps Codex SDK stream events into normalized `Jido.Harness.Event` structs.
  """

  alias Codex.Events
  alias Codex.Items
  alias Codex.StreamEvent
  alias Jido.Harness.Event
  alias Jido.Harness.Event.Usage, as: UsageEvent

  @doc "Maps a Codex stream event into one or more normalized events."
  @spec map_event(term(), keyword()) :: {:ok, [Event.t()]} | {:error, term()}
  def map_event(%StreamEvent.RunItem{event: event}, opts), do: map_event(event, opts)

  def map_event(%StreamEvent.RawResponses{events: events}, opts) when is_list(events) do
    events
    |> Enum.reduce_while({:ok, []}, fn event, {:ok, acc} ->
      case map_event(event, opts) do
        {:ok, mapped} -> {:cont, {:ok, acc ++ mapped}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def map_event(%StreamEvent.AgentUpdated{} = event, _opts) do
    {:ok, [build_event(:codex_event, nil, %{"event_type" => "agent_updated"}, event)]}
  end

  def map_event(%StreamEvent.GuardrailResult{} = event, _opts) do
    payload = %{
      "event_type" => "guardrail_result",
      "stage" => event.stage,
      "guardrail" => event.guardrail,
      "result" => event.result,
      "message" => event.message
    }

    {:ok, [build_event(:codex_event, nil, payload, event)]}
  end

  def map_event(%StreamEvent.ToolApproval{} = event, _opts) do
    payload = %{
      "event_type" => "tool_approval",
      "tool_name" => event.tool_name,
      "call_id" => event.call_id,
      "decision" => event.decision,
      "reason" => event.reason
    }

    {:ok, [build_event(:codex_event, nil, payload, event)]}
  end

  def map_event(%Events.ThreadStarted{} = event, _opts) do
    payload = %{"session_id" => event.thread_id, "cwd" => nil}
    {:ok, [build_event(:session_started, event.thread_id, payload, event)]}
  end

  def map_event(%Events.SessionConfigured{} = event, _opts) do
    payload = %{"session_id" => event.session_id, "cwd" => event.cwd}
    {:ok, [build_event(:session_started, event.session_id, payload, event)]}
  end

  def map_event(%Events.TurnStarted{} = event, _opts) do
    payload = %{"turn_id" => event.turn_id}
    {:ok, [build_event(:codex_turn_started, event.thread_id, payload, event)]}
  end

  def map_event(%Events.TurnContinuation{} = event, _opts) do
    payload = %{
      "turn_id" => event.turn_id,
      "continuation_token" => event.continuation_token,
      "retryable" => event.retryable,
      "reason" => event.reason
    }

    {:ok, [build_event(:codex_turn_continuation, event.thread_id, payload, event)]}
  end

  def map_event(%Events.ItemAgentMessageDelta{} = event, _opts) do
    case item_text_delta(event.item) do
      nil -> {:ok, []}
      text -> {:ok, [build_event(:output_text_delta, event.thread_id, %{"text" => text}, event)]}
    end
  end

  def map_event(%Events.ItemCompleted{item: %Items.AgentMessage{} = item} = event, _opts) do
    {:ok, [build_event(:output_text_final, event.thread_id, %{"text" => item.text}, event)]}
  end

  def map_event(%Events.ItemCompleted{item: %Items.Reasoning{} = item} = event, _opts) do
    text = item.text || Enum.join(item.summary ++ item.content, "\n")
    {:ok, [build_event(:thinking_delta, event.thread_id, %{"text" => text}, event)]}
  end

  # Exec-transport command execution: emit both a tool_call and tool_result
  # from the completed item since it contains the full command, output, and exit code.
  def map_event(%Events.ItemCompleted{item: %Items.CommandExecution{} = item} = event, _opts) do
    call_id = item.id || "exec-#{System.unique_integer([:positive])}"

    tool_call =
      build_event(
        :tool_call,
        event.thread_id,
        %{
          "name" => "exec_command",
          "input" => %{"cmd" => item.command, "cwd" => item.cwd},
          "call_id" => call_id
        },
        event
      )

    tool_result =
      build_event(
        :tool_result,
        event.thread_id,
        %{
          "name" => "exec_command",
          "output" => item.aggregated_output || "",
          "call_id" => call_id,
          "is_error" => item.status == :failed || (item.exit_code != nil and item.exit_code != 0)
        },
        event
      )

    {:ok, [tool_call, tool_result]}
  end

  # McpToolCall items from exec transport
  def map_event(%Events.ItemCompleted{item: %Items.McpToolCall{} = item} = event, _opts) do
    call_id = item.id || "mcp-#{System.unique_integer([:positive])}"

    tool_call =
      build_event(
        :tool_call,
        event.thread_id,
        %{
          "name" => item.name || "mcp_tool",
          "input" => item.arguments || %{},
          "call_id" => call_id
        },
        event
      )

    tool_result =
      build_event(
        :tool_result,
        event.thread_id,
        %{
          "name" => item.name || "mcp_tool",
          "output" => item.output || "",
          "call_id" => call_id,
          "is_error" => item.status == :failed
        },
        event
      )

    {:ok, [tool_call, tool_result]}
  end

  # In-progress command execution (item.started) — skip since ItemCompleted
  # will emit both tool_call and tool_result with complete data
  def map_event(%Events.ItemStarted{item: %Items.CommandExecution{}}, _opts), do: {:ok, []}

  # Skip other ItemStarted/ItemUpdated (noise for rendering)
  def map_event(%Events.ItemStarted{}, _opts), do: {:ok, []}
  def map_event(%Events.ItemUpdated{}, _opts), do: {:ok, []}

  def map_event(%Events.ReasoningDelta{} = event, _opts) do
    {:ok, [build_event(:thinking_delta, event.thread_id, %{"text" => event.delta}, event)]}
  end

  def map_event(%Events.ToolCallRequested{} = event, _opts) do
    payload = %{
      "name" => event.tool_name,
      "input" => event.arguments,
      "call_id" => event.call_id,
      "requires_approval" => event.requires_approval
    }

    {:ok, [build_event(:tool_call, event.thread_id, payload, event)]}
  end

  def map_event(%Events.ToolCallCompleted{} = event, _opts) do
    payload = %{
      "name" => event.tool_name,
      "output" => event.output,
      "is_error" => false,
      "call_id" => event.call_id
    }

    {:ok, [build_event(:tool_result, event.thread_id, payload, event)]}
  end

  def map_event(%Events.ItemCompleted{item: %Items.FileChange{} = item} = event, _opts) do
    payload = %{"changes" => item.changes, "status" => item.status}
    {:ok, [build_event(:file_change, event.thread_id, payload, event)]}
  end

  def map_event(%Events.ThreadTokenUsageUpdated{} = event, _opts) do
    payload = %{"usage" => event.usage, "delta" => event.delta}
    {:ok, [build_event(:codex_token_update, event.thread_id, payload, event)]}
  end

  def map_event(%Events.AccountRateLimitsUpdated{} = event, _opts) do
    payload = %{"rate_limits" => event.rate_limits}
    {:ok, [build_event(:codex_rate_limits_updated, event.thread_id, payload, event)]}
  end

  def map_event(%Events.TurnDiffUpdated{} = event, _opts) do
    {:ok, [build_event(:codex_turn_diff_updated, event.thread_id, %{"diff" => event.diff}, event)]}
  end

  def map_event(%Events.TurnPlanUpdated{} = event, _opts) do
    payload = %{"explanation" => event.explanation, "plan" => event.plan}
    {:ok, [build_event(:codex_turn_plan_updated, event.thread_id, payload, event)]}
  end

  def map_event(%Events.McpToolCallProgress{} = event, _opts) do
    {:ok,
     [
       build_event(
         :codex_mcp_tool_progress,
         event.thread_id,
         %{"message" => event.message, "item_id" => event.item_id},
         event
       )
     ]}
  end

  def map_event(%Events.RequestUserInput{} = event, _opts) do
    {:ok,
     [
       build_event(
         :codex_request_user_input,
         nil,
         %{"id" => event.id, "turn_id" => event.turn_id, "questions" => event.questions},
         event
       )
     ]}
  end

  def map_event(%Events.ConfigWarning{} = event, _opts) do
    payload = %{"summary" => event.summary, "details" => event.details}
    {:ok, [build_event(:codex_warning, nil, payload, event)]}
  end

  def map_event(%Events.Warning{} = event, _opts) do
    payload = %{"summary" => event.message, "details" => nil}
    {:ok, [build_event(:codex_warning, nil, payload, event)]}
  end

  def map_event(%Events.TurnCompleted{} = event, _opts) do
    payload = %{
      "session_id" => event.thread_id,
      "status" => event.status,
      "response_id" => event.response_id,
      "usage" => event.usage
    }

    usage_event = maybe_usage_event(event.usage, event.thread_id, event)

    {:ok, List.wrap(usage_event) ++ [build_event(:session_completed, event.thread_id, payload, event)]}
  end

  def map_event(%Events.TurnFailed{} = event, _opts) do
    {:ok, [build_event(:session_failed, event.thread_id, %{"error" => event.error}, event)]}
  end

  def map_event(%Events.Error{} = event, _opts) do
    payload = %{
      "error" => %{
        "message" => event.message,
        "additional_details" => event.additional_details,
        "codex_error_info" => event.codex_error_info,
        "will_retry" => event.will_retry
      }
    }

    {:ok, [build_event(:session_failed, event.thread_id, payload, event)]}
  end

  def map_event(%Events.TurnAborted{} = event, _opts) do
    {:ok, [build_event(:session_cancelled, nil, %{"reason" => event.reason, "turn_id" => event.turn_id}, event)]}
  end

  def map_event(event, _opts) do
    payload = %{"event_module" => detect_event_module(event), "event_type" => detect_event_type(event)}
    session_id = detect_session_id(event)
    {:ok, [build_event(:codex_event, session_id, payload, event)]}
  end

  defp build_event(type, session_id, payload, raw) do
    Event.new!(%{
      type: type,
      provider: :codex,
      session_id: session_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      payload: stringify_keys(payload),
      raw: raw
    })
  end

  defp item_text_delta(item) when is_map(item) do
    item[:delta] || item["delta"] || item[:text] || item["text"]
  end

  defp item_text_delta(_), do: nil

  defp detect_event_module(%{__struct__: module}), do: inspect(module)
  defp detect_event_module(_), do: "unknown"

  defp detect_event_type(event) when is_map(event) do
    Map.get(event, :type) || Map.get(event, "type") || "unknown"
  end

  defp detect_event_type(_), do: "unknown"

  defp detect_session_id(event) when is_map(event) do
    Map.get(event, :thread_id) || Map.get(event, "thread_id") || Map.get(event, :session_id) ||
      Map.get(event, "session_id")
  end

  defp detect_session_id(_), do: nil

  defp maybe_usage_event(nil, _session_id, _raw), do: nil

  defp maybe_usage_event(usage, session_id, raw) when is_map(usage) and is_binary(session_id) do
    input = usage["input_tokens"] || usage[:input_tokens] || 0
    output = usage["output_tokens"] || usage[:output_tokens] || 0
    cached = usage["cached_input_tokens"] || usage[:cached_input_tokens] || 0

    if input > 0 or output > 0 do
      UsageEvent.build(:codex, session_id,
        input_tokens: input,
        output_tokens: output,
        cached_input_tokens: cached,
        raw: raw
      )
    else
      nil
    end
  end

  defp maybe_usage_event(_, _, _), do: nil

  defp stringify_keys(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {to_string(k), stringify_keys(v)} end)
    |> Map.new()
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
