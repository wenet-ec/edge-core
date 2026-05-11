# edge_agent/mix.exs
defmodule EdgeAgent.Mixfile do
  use Mix.Project

  def project do
    [
      app: :edge_agent,
      version: "0.2.0",
      erlang: "~> 28.5",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_paths: ["test"],
      test_pattern: "**/*_test.exs",
      test_coverage: [tool: ExCoveralls],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: dialyzer(),
      releases: releases(),
      listeners: [Phoenix.CodeReloader],
      package: package()
    ]
  end

  def cli do
    [
      preferred_envs: [
        precommit: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      mod: {EdgeAgent.Application, []},
      extra_applications: [:logger, :runtime_tools, :ssh, :crypto, :public_key]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{},
      files: ~w(lib priv config mix.exs LICENSE NOTICE)
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate", "test --warnings-as-errors"],
      lint: ["compile --warnings-as-errors", "credo --strict"],
      quality: ["format --check-formatted", "credo --strict", "dialyzer"],
      security: ["deps.audit", "sobelow --config"],
      check: [
        "format --check-formatted",
        "deps.unlock --check-unused",
        "deps.audit",
        "sobelow --config",
        "compile --warnings-as-errors",
        "credo --strict",
        "dialyzer"
      ],
      precommit: [
        "check",
        "test"
      ]
    ]
  end

  defp deps do
    [
      # HTTP Client
      {:req, "~> 0.5"},

      # HTTP server
      {:bandit, "~> 1.11"},
      {:ranch, "~> 2.2"},
      {:phoenix, "~> 1.8"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:jason, "~> 1.4"},
      {:plug_checkup, git: "https://github.com/voughtdq/plug_checkup.git", tag: "v1.0.0"},

      # Database
      {:phoenix_ecto, "~> 4.7"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, "~> 0.23"},
      {:uniq, "~> 0.6"},
      {:excellent_migrations, "~> 0.1", only: [:dev, :test], runtime: false},

      # Background jobs
      {:oban, "~> 2.22"},

      # SSH server
      {:erlexec, "~> 2.3", runtime: Mix.env() != :test},

      # Telemetry
      {:prom_ex, "~> 1.11"},

      # Linting
      {:credo, "~> 1.7", only: [:dev, :test], override: true},
      {:credo_envvar, "~> 0.1", only: [:dev, :test], runtime: false},
      {:credo_naming, "~> 2.1", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.11", only: [:dev, :test], runtime: false},

      # Security check
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: true},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},

      # Test factories
      {:ex_machina, "~> 2.8", only: :test},
      {:faker, "~> 0.18", only: :test},
      {:mox, "~> 1.2", only: :test},

      # Test coverage
      {:excoveralls, "~> 0.18", only: :test},

      # Dialyzer
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},

      # LAN discovery and DNS
      {:mdns_lite, "~> 0.9"},

      # Nexmaker library
      {:nexmaker, path: "../nexmaker"}
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/edge_agent.plt"},
      plt_add_apps: [:mix, :ex_unit]
    ]
  end

  defp releases do
    [
      edge_agent: [
        version: {:from_app, :edge_agent},
        applications: [edge_agent: :permanent],
        include_executables_for: [:unix],
        steps: [:assemble, :tar]
      ]
    ]
  end
end
