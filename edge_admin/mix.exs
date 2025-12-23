# edge_admin/mix.exs
defmodule EdgeAdmin.Mixfile do
  use Mix.Project

  def project do
    [
      app: :edge_admin,
      version: "0.2.0",
      erlang: "~> 28.2",
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
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def application do
    [
      mod: {EdgeAdmin.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [preferred_envs: [coveralls: :test, "coveralls.detail": :test, "coveralls.post": :test, "coveralls.html": :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

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
      # HTTP Client/Wrapper
      {:req, "~> 0.5"},

      # HTTP server
      {:bandit, "~> 1.8"},
      {:corsica, "~> 2.1"},
      {:ranch, "~> 2.2"},

      # Phoenix
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_ecto, "~> 4.7"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:jason, "~> 1.4"},
      {:argon2_elixir, "~> 4.1"},

      # API
      {:open_api_spex, "~> 3.22"},
      {:redoc_ui_plug, "~> 0.2"},

      # Database
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.21"},
      {:flop, "~> 0.26"},

      # Database check
      {:excellent_migrations, "~> 0.1", only: [:dev, :test], runtime: false},

      # Translations
      {:gettext, "~> 1.0"},

      # Errors
      {:hackney, "~> 1.25"},
      {:sentry, "~> 11.0"},

      # Telemetry
      {:prom_ex, "~> 1.11"},
      {:telemetry_ui, "~> 5.3"},

      # Linting
      {:credo, "~> 1.7", only: [:dev, :test], override: true},
      {:credo_envvar, "~> 0.1", only: [:dev, :test], runtime: false},
      {:credo_naming, "~> 2.1", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.10", only: [:dev, :test], runtime: false},

      # Security check
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: true},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},

      # Health
      {:plug_checkup, git: "https://github.com/voughtdq/plug_checkup.git", tag: "v1.0.0"},

      # Test factories
      {:ex_machina, "~> 2.8", only: :test},
      {:faker, "~> 0.18", only: :test},
      {:mox, "~> 1.2", only: :test},

      # Test coverage
      {:excoveralls, "~> 0.18", only: :test},

      # Dialyzer
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},

      # DNS Cluster
      {:dns_cluster, "~> 0.2"},

      # Background Jobs
      {:oban, "~> 2.20"},
      {:quantum, "~> 3.5"},

      # Erlang Distribution
      {:syn, "~> 3.3"},

      # Nexmaker library
      {:nexmaker, path: "../nexmaker"}
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/edge_admin.plt"},
      plt_add_apps: [:mix, :ex_unit]
    ]
  end

  defp releases do
    [
      edge_admin: [
        version: {:from_app, :edge_admin},
        applications: [edge_admin: :permanent],
        include_executables_for: [:unix],
        steps: [:assemble, :tar]
      ]
    ]
  end
end
