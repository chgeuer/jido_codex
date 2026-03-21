defmodule Jido.Codex.AdapterTest do
  use ExUnit.Case, async: false

  use Jido.Harness.AdapterContract,
    adapter: Jido.Codex.Adapter,
    provider: :codex,
    check_run: true,
    run_request: %{prompt: "contract codex run", cwd: "/repo", metadata: %{}}

  alias Jido.Codex.{Adapter, SessionRegistry}

  alias Jido.Codex.Test.{
    Fixtures,
    StubAppServer,
    StubCodex,
    StubCodexOptions,
    StubCodexThread,
    StubCompatibility,
    StubMapper,
    StubRunResultModule
  }

  setup do
    old_compat_module = Application.get_env(:jido_codex, :compatibility_module)
    old_codex_module = Application.get_env(:jido_codex, :codex_module)
    old_codex_options_module = Application.get_env(:jido_codex, :codex_options_module)
    old_codex_thread_module = Application.get_env(:jido_codex, :codex_thread_module)
    old_run_result_module = Application.get_env(:jido_codex, :codex_run_result_module)
    old_app_server_module = Application.get_env(:jido_codex, :codex_app_server_module)
    old_mapper_module = Application.get_env(:jido_codex, :mapper_module)

    old_stub_compat_check = Application.get_env(:jido_codex, :stub_compat_check)
    old_stub_codex_options_new = Application.get_env(:jido_codex, :stub_codex_options_new)
    old_stub_codex_start_thread = Application.get_env(:jido_codex, :stub_codex_start_thread)
    old_stub_codex_resume_thread = Application.get_env(:jido_codex, :stub_codex_resume_thread)
    old_stub_codex_thread_run_streamed = Application.get_env(:jido_codex, :stub_codex_thread_run_streamed)
    old_stub_run_result_events = Application.get_env(:jido_codex, :stub_run_result_events)
    old_stub_run_result_cancel = Application.get_env(:jido_codex, :stub_run_result_cancel)
    old_stub_app_server_connect = Application.get_env(:jido_codex, :stub_app_server_connect)
    old_stub_app_server_disconnect = Application.get_env(:jido_codex, :stub_app_server_disconnect)
    old_stub_mapper_map_event = Application.get_env(:jido_codex, :stub_mapper_map_event)

    Application.put_env(:jido_codex, :compatibility_module, StubCompatibility)
    Application.put_env(:jido_codex, :codex_module, StubCodex)
    Application.put_env(:jido_codex, :codex_options_module, StubCodexOptions)
    Application.put_env(:jido_codex, :codex_thread_module, StubCodexThread)
    Application.put_env(:jido_codex, :codex_run_result_module, StubRunResultModule)
    Application.put_env(:jido_codex, :codex_app_server_module, StubAppServer)
    Application.put_env(:jido_codex, :mapper_module, StubMapper)

    Application.put_env(:jido_codex, :stub_compat_check, fn _transport -> :ok end)
    Application.put_env(:jido_codex, :stub_codex_options_new, fn attrs -> {:ok, attrs} end)

    Application.put_env(:jido_codex, :stub_codex_start_thread, fn codex_opts, thread_opts ->
      send(self(), {:start_thread, codex_opts, thread_opts})
      {:ok, %{thread: :new, thread_opts: thread_opts}}
    end)

    Application.put_env(:jido_codex, :stub_codex_resume_thread, fn thread_id, codex_opts, thread_opts ->
      send(self(), {:resume_thread, thread_id, codex_opts, thread_opts})
      {:ok, %{thread: :resumed, thread_id: thread_id, thread_opts: thread_opts}}
    end)

    Application.put_env(:jido_codex, :stub_codex_thread_run_streamed, fn _thread, prompt, turn_opts ->
      send(self(), {:run_streamed, prompt, turn_opts})
      {:ok, %{events: [Fixtures.run_item(Fixtures.thread_started("session-1")), Fixtures.turn_completed("session-1")]}}
    end)

    Application.put_env(:jido_codex, :stub_run_result_events, fn rr -> rr.events end)

    Application.put_env(:jido_codex, :stub_run_result_cancel, fn run_result, mode ->
      send(self(), {:cancel_called, run_result, mode})
      :ok
    end)

    Application.put_env(:jido_codex, :stub_app_server_connect, fn _opts, app_server_opts ->
      send(self(), {:app_server_connect, app_server_opts})
      {:ok, self()}
    end)

    Application.put_env(:jido_codex, :stub_app_server_disconnect, fn connection ->
      send(self(), {:app_server_disconnect, connection})
      :ok
    end)

    Application.put_env(:jido_codex, :stub_mapper_map_event, fn event, _opts ->
      Jido.Codex.Mapper.map_event(event, [])
    end)

    SessionRegistry.clear()

    on_exit(fn ->
      restore_env(:jido_codex, :compatibility_module, old_compat_module)
      restore_env(:jido_codex, :codex_module, old_codex_module)
      restore_env(:jido_codex, :codex_options_module, old_codex_options_module)
      restore_env(:jido_codex, :codex_thread_module, old_codex_thread_module)
      restore_env(:jido_codex, :codex_run_result_module, old_run_result_module)
      restore_env(:jido_codex, :codex_app_server_module, old_app_server_module)
      restore_env(:jido_codex, :mapper_module, old_mapper_module)

      restore_env(:jido_codex, :stub_compat_check, old_stub_compat_check)
      restore_env(:jido_codex, :stub_codex_options_new, old_stub_codex_options_new)
      restore_env(:jido_codex, :stub_codex_start_thread, old_stub_codex_start_thread)
      restore_env(:jido_codex, :stub_codex_resume_thread, old_stub_codex_resume_thread)
      restore_env(:jido_codex, :stub_codex_thread_run_streamed, old_stub_codex_thread_run_streamed)
      restore_env(:jido_codex, :stub_run_result_events, old_stub_run_result_events)
      restore_env(:jido_codex, :stub_run_result_cancel, old_stub_run_result_cancel)
      restore_env(:jido_codex, :stub_app_server_connect, old_stub_app_server_connect)
      restore_env(:jido_codex, :stub_app_server_disconnect, old_stub_app_server_disconnect)
      restore_env(:jido_codex, :stub_mapper_map_event, old_stub_mapper_map_event)
      SessionRegistry.clear()
    end)

    :ok
  end

  test "id/0 and capabilities/0" do
    assert Adapter.id() == :codex

    caps = Adapter.capabilities()
    assert caps.streaming? == true
    assert caps.tool_calls? == true
    assert caps.cancellation? == true
  end

  test "runtime_contract/0 exposes codex runtime requirements" do
    contract = Adapter.runtime_contract()
    assert contract.provider == :codex
    assert "OPENAI_API_KEY" in contract.host_env_required_any
    assert "codex" in contract.runtime_tools_required
    assert is_list(contract.compatibility_probes)
    assert Enum.any?(contract.compatibility_probes, &(&1["command"] == "codex --help || codex exec --help"))

    assert Enum.any?(contract.auth_bootstrap_steps, fn step ->
             String.contains?(step, "codex login --with-api-key")
           end)

    assert String.contains?(contract.triage_command_template, "codex exec --json")
    assert String.contains?(contract.coding_command_template, "--dangerously-bypass-approvals-and-sandbox")
  end

  test "run/2 executes in exec mode and maps events" do
    request = Jido.Harness.RunRequest.new!(%{prompt: "hello", metadata: %{}})

    assert {:ok, stream} = Adapter.run(request)
    events = Enum.to_list(stream)

    assert_receive {:start_thread, _codex_opts, thread_opts}
    assert thread_opts[:transport] == nil
    assert_receive {:run_streamed, "hello", %{}}

    assert Enum.map(events, & &1.type) == [:session_started, :usage, :session_completed]
    assert events |> Enum.at(0) |> Map.get(:session_id) == "session-1"
  end

  test "run/2 uses resume by thread_id" do
    request =
      Jido.Harness.RunRequest.new!(%{
        prompt: "hello",
        metadata: %{"codex" => %{"thread_id" => "thread-123"}}
      })

    assert {:ok, stream} = Adapter.run(request)
    _ = Enum.to_list(stream)

    assert_receive {:resume_thread, "thread-123", _codex_opts, _thread_opts}
  end

  test "run/2 uses resume_last when configured" do
    request =
      Jido.Harness.RunRequest.new!(%{
        prompt: "hello",
        metadata: %{"codex" => %{"resume_last" => true}}
      })

    assert {:ok, stream} = Adapter.run(request)
    _ = Enum.to_list(stream)

    assert_receive {:resume_thread, :last, _codex_opts, _thread_opts}
  end

  test "run/2 uses app_server transport and disconnects after stream" do
    request =
      Jido.Harness.RunRequest.new!(%{
        prompt: "hello",
        metadata: %{"codex" => %{"transport" => "app_server", "app_server" => %{"client_name" => "test"}}}
      })

    assert {:ok, stream} = Adapter.run(request)
    _ = Enum.to_list(stream)

    assert_receive {:app_server_connect, [{"client_name", "test"}]}
    assert_receive {:start_thread, _codex_opts, thread_opts}
    assert {:app_server, _pid} = thread_opts[:transport]
    assert_receive {:app_server_disconnect, _pid}
  end

  test "cancel/1 cancels registered session" do
    SessionRegistry.register("session-1", %{
      run_result: %{id: 1},
      run_result_module: StubRunResultModule,
      cancel_mode: :after_turn,
      app_server_connection: nil
    })

    assert :ok = Adapter.cancel("session-1")
    assert_receive {:cancel_called, %{id: 1}, :after_turn}
    assert {:error, :not_found} = SessionRegistry.fetch("session-1")
  end

  test "cancel/1 returns error when unknown" do
    assert {:error, %Jido.Codex.Error.ExecutionFailureError{}} = Adapter.cancel("missing")
  end

  test "cancel/1 validates non-string session ids" do
    assert {:error, %Jido.Codex.Error.InvalidInputError{}} = Adapter.cancel(:bad)
  end

  test "run/2 returns error when compatibility fails" do
    Application.put_env(:jido_codex, :stub_compat_check, fn _transport ->
      {:error, Jido.Codex.Error.config_error("bad compat", %{key: :compat})}
    end)

    request = Jido.Harness.RunRequest.new!(%{prompt: "hello", metadata: %{}})
    assert {:error, %Jido.Codex.Error.ConfigError{key: :compat}} = Adapter.run(request)
  end

  test "run/2 returns execution error when app-server connect fails" do
    Application.put_env(:jido_codex, :stub_app_server_connect, fn _opts, _app_server_opts ->
      {:error, :connection_refused}
    end)

    request =
      Jido.Harness.RunRequest.new!(%{
        prompt: "hello",
        metadata: %{"codex" => %{"transport" => "app_server"}}
      })

    assert {:error, %Jido.Codex.Error.ExecutionFailureError{}} = Adapter.run(request)
  end

  test "run/2 returns thread run errors" do
    Application.put_env(:jido_codex, :stub_codex_thread_run_streamed, fn _thread, _prompt, _turn_opts ->
      {:error, :stream_failed}
    end)

    request = Jido.Harness.RunRequest.new!(%{prompt: "hello", metadata: %{}})
    assert {:error, :stream_failed} = Adapter.run(request)
  end

  test "run/2 rescues argument errors into validation errors" do
    Application.put_env(:jido_codex, :stub_codex_options_new, fn _attrs ->
      raise ArgumentError, "bad options"
    end)

    request = Jido.Harness.RunRequest.new!(%{prompt: "hello", metadata: %{}})

    assert {:error, %Jido.Codex.Error.InvalidInputError{message: "Invalid run request"}} = Adapter.run(request)
  end

  test "run/2 emits session_failed events when mapper returns errors" do
    Application.put_env(:jido_codex, :stub_mapper_map_event, fn _event, _opts ->
      {:error, :mapper_failed}
    end)

    request = Jido.Harness.RunRequest.new!(%{prompt: "hello", metadata: %{}})
    assert {:ok, stream} = Adapter.run(request)

    events = Enum.to_list(stream)
    assert Enum.all?(events, &(&1.type == :session_failed))
    assert Enum.all?(events, &(&1.payload["error"] =~ "mapper_failed"))
  end

  test "run/2 handles streams without session identifiers" do
    Application.put_env(:jido_codex, :stub_run_result_events, fn _rr ->
      [Fixtures.warning()]
    end)

    request = Jido.Harness.RunRequest.new!(%{prompt: "hello", metadata: %{}})
    assert {:ok, stream} = Adapter.run(request)

    events = Enum.to_list(stream)
    assert Enum.map(events, & &1.type) == [:codex_warning]
    assert SessionRegistry.list() == []
  end

  test "run/2 cleans registered sessions when stream is halted early" do
    Application.put_env(:jido_codex, :stub_run_result_events, fn _rr ->
      Stream.cycle([Fixtures.run_item(Fixtures.thread_started("session-1"))])
    end)

    request = Jido.Harness.RunRequest.new!(%{prompt: "hello", metadata: %{}})
    assert {:ok, stream} = Adapter.run(request)
    assert [_first] = Enum.take(stream, 1)
    assert SessionRegistry.list() == []
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
