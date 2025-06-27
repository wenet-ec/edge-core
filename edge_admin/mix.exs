# edge_admin/mix.exs
defmodule EdgeAdmin.Mixfile do
  use Mix.Project

  def project do
    [
      app: :edge_admin,
      version: "0.0.1",
      erlang: "~> 26.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_paths: ["test"],
      test_pattern: "**/*_test.exs",
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [coveralls: :test, "coveralls.detail": :test, "coveralls.post": :test, "coveralls.html": :test],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: dialyzer(),
      releases: releases()
    ]
  end

  def application do
    [
      mod: {EdgeAdmin.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate", "test --warnings-as-errors"]
    ]
  end

  defp deps do
    [
      # HTTP Client/Wrapper
      {:req, "~> 0.5.0"},

      # HTTP server
      {:bandit, "~> 1.6"},
      {:corsica, "~> 2.1"},

      # Phoenix
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.2"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_ecto, "~> 4.6"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:jason, "~> 1.4"},

      # API
      {:open_api_spex, "~> 3.21"},

      # Database
      {:ecto_sql, "~> 3.12"},
      {:postgrex, "~> 0.20"},

      # Database check
      {:excellent_migrations, "~> 0.1", only: [:dev, :test], runtime: false},

      # Translations
      {:gettext, "~> 0.26"},

      # Errors
      {:sentry, "~> 10.10"},

      # Telemetry
      {:prom_ex, "~> 1.11"},
      {:telemetry_ui, "~> 5.0"},

      # Linting
      {:credo, "~> 1.7", only: [:dev, :test], override: true},
      {:credo_envvar, "~> 0.1", only: [:dev, :test], runtime: false},
      {:credo_naming, "~> 2.1", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.4", only: [:dev, :test], runtime: false},

      # Security check
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: true},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},

      # Health
      {:plug_checkup, "~> 0.6"},

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

      # Oban
      {:oban, "~> 2.19"}
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
