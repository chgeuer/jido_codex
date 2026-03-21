defmodule Jido.Codex.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/agentjido/jido_codex"
  @description "OpenAI Codex CLI adapter for Jido.Harness"

  def project do
    [
      app: :jido_codex,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "Jido.Codex",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: [
        main: "Jido.Codex",
        extras: ["README.md", "CHANGELOG.md", "guides/getting-started.md"],
        formatters: ["html"]
      ],
      dialyzer: [
        plt_add_apps: [:mix]
      ],
      test_coverage: [
        tool: ExCoveralls,
        summary: [threshold: 90]
      ],
      description: @description,
      package: [
        name: :jido_codex,
        description: @description,
        files: [
          ".formatter.exs",
          "CHANGELOG.md",
          "CONTRIBUTING.md",
          "LICENSE",
          "README.md",
          "config",
          "guides",
          "lib",
          "mix.exs",
          "usage-rules.md"
        ],
        licenses: ["Apache-2.0"],
        links: %{"GitHub" => @source_url}
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.github": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    runtime_deps() ++ dev_test_deps()
  end

  defp runtime_deps do
    [
      {:zoi, "~> 0.17"},
      {:splode, ">= 0.2.9 and < 0.4.0"},
      {:jido_harness, path: "../jido_harness", override: true},
      {:jido_shell, github: "agentjido/jido_shell", branch: "main", override: true},
      {:codex_sdk, "~> 0.10"},
      {:jason, "~> 1.4"}
    ]
  end

  defp dev_test_deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:doctor, "~> 0.21", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "git_hooks.install"],
      q: ["quality"],
      quality: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --min-priority higher",
        "dialyzer",
        "doctor --raise"
      ],
      test: ["test --cover --color"],
      "test.watch": ["watch -c \"mix test\""]
    ]
  end
end
