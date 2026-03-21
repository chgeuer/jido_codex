defmodule Jido.Codex.Compatibility do
  @moduledoc """
  Runtime compatibility checks for local Codex CLI features.

  Supported transports:
  - `:exec` (requires `exec` and `--json` in CLI help)
  - `:app_server` (requires `app-server` in CLI help)
  """

  alias Jido.Codex.Error
  alias Jido.Codex.Error.ConfigError

  @command_timeout 5_000
  @required_tokens %{exec: ["exec", "--json"], app_server: ["app-server"]}

  @spec status(:exec | :app_server) :: {:ok, map()} | {:error, ConfigError.t()}
  @doc "Returns compatibility metadata for the requested transport."
  def status(transport \\ :exec) do
    with {:ok, normalized_transport} <- normalize_transport(transport),
         {:ok, spec} <- resolve_cli(),
         {:ok, help_output} <- read_help(spec.program),
         :ok <- ensure_transport_support(normalized_transport, help_output) do
      {:ok,
       %{
         program: spec.program,
         version: read_version(spec.program),
         transport: normalized_transport,
         required_tokens: @required_tokens[normalized_transport]
       }}
    end
  end

  @spec check(:exec | :app_server) :: :ok | {:error, ConfigError.t()}
  @doc "Returns :ok when compatible, otherwise a structured config error."
  def check(transport \\ :exec) do
    case status(transport) do
      {:ok, _} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @spec compatible?(:exec | :app_server) :: boolean()
  @doc "Boolean predicate for compatibility checks."
  def compatible?(transport \\ :exec), do: match?({:ok, _}, status(transport))

  @spec assert_compatible!(:exec | :app_server) :: :ok | no_return()
  @doc "Raises when the requested transport is not compatible."
  def assert_compatible!(transport \\ :exec) do
    case check(transport) do
      :ok -> :ok
      {:error, error} -> raise error
    end
  end

  @spec cli_installed?() :: boolean()
  @doc "Returns true when a Codex CLI binary can be resolved."
  def cli_installed?, do: match?({:ok, _}, resolve_cli())

  @doc false
  @spec cli_module() :: module()
  def cli_module do
    Application.get_env(:jido_codex, :codex_cli_module, Jido.Codex.CLI)
  end

  @doc false
  @spec command_module() :: module()
  def command_module do
    Application.get_env(:jido_codex, :codex_command_module, Jido.Codex.SystemCommand)
  end

  defp normalize_transport(:exec), do: {:ok, :exec}
  defp normalize_transport(:app_server), do: {:ok, :app_server}
  defp normalize_transport("exec"), do: {:ok, :exec}
  defp normalize_transport("app_server"), do: {:ok, :app_server}
  defp normalize_transport("app-server"), do: {:ok, :app_server}

  defp normalize_transport(other) do
    {:error,
     Error.config_error("Unknown Codex transport for compatibility check", %{
       key: :transport,
       details: %{transport: other}
     })}
  end

  defp resolve_cli do
    case cli_module().resolve() do
      {:ok, spec} ->
        {:ok, spec}

      {:error, reason} ->
        {:error,
         Error.config_error("Codex CLI is not available. Install Codex and run `mix codex.install`.", %{
           key: :codex_cli,
           details: %{reason: reason}
         })}
    end
  end

  defp read_help(program) do
    # Check both top-level and exec subcommand help, since flags like --json
    # are defined on the exec subcommand, not the top-level command.
    with {:ok, top_help} <- run_help(program, ["--help"]),
         {:ok, exec_help} <- run_help(program, ["exec", "--help"]) do
      {:ok, top_help <> "\n" <> exec_help}
    else
      # If exec --help fails, fall back to top-level only
      {:error, _} ->
        run_help(program, ["--help"])
    end
  end

  defp run_help(program, args) do
    case command_module().run(program, args, timeout: @command_timeout) do
      {:ok, output} ->
        {:ok, output}

      {:error, reason} ->
        {:error,
         Error.config_error("Unable to read Codex CLI help output.", %{
           key: :codex_cli_help,
           details: %{reason: reason}
         })}
    end
  end

  defp ensure_transport_support(transport, help_output) do
    missing = Enum.reject(@required_tokens[transport], &String.contains?(help_output, &1))

    case missing do
      [] ->
        :ok

      _ ->
        {:error,
         Error.config_error("Installed Codex CLI is incompatible with requested transport.", %{
           key: :codex_cli_transport_compatibility,
           details: %{transport: transport, missing_tokens: missing}
         })}
    end
  end

  defp read_version(program) do
    case command_module().run(program, ["--version"], timeout: @command_timeout) do
      {:ok, version} -> String.trim(version)
      {:error, _} -> "unknown"
    end
  end
end
