# edge_admin/mix.exs
defmodule EdgeAdmin.Mixfile do
  use Mix.Project

  def project do
    [
      app: :edge_admin,
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
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def application do
    [
      mod: {EdgeAdmin.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate", "test --warnings-as-errors --max-failures 1"],
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
      {:bandit, "~> 1.11"},
      {:corsica, "~> 2.1"},
      {:ranch, "~> 2.2"},

      # Phoenix
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_ecto, "~> 4.7"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:jason, "~> 1.4"},
      {:argon2_elixir, "~> 4.1"},

      # API and MCP
      {:open_api_spex, "~> 3.22"},
      {:redoc_ui_plug, "~> 0.2"},
      {:anubis_mcp, "~> 1.3"},

      # Database
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.22"},
      {:ecto_sqlite3, "~> 0.22"},
      {:uniq, "~> 0.6"},
      {:flop, "~> 0.26"},

      # Database check
      {:excellent_migrations, "~> 0.1", only: [:dev, :test], runtime: false},

      # Errors
      {:sentry, "~> 13.0"},

      # Telemetry
      {:prom_ex, "~> 1.11"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:ecto_psql_extras, "~> 0.8"},
      {:ecto_sqlite3_extras, "~> 1.2"},
      {:oban_live_dashboard, "~> 0.2.1"},

      # Linting
      {:credo, "~> 1.7", only: [:dev, :test], override: true},
      {:credo_envvar, "~> 0.1", only: [:dev, :test], runtime: false},
      {:credo_naming, "~> 2.1", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.11", only: [:dev, :test], runtime: false},

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

      # Background Jobs
      {:oban, "~> 2.22"},
      {:quantum, "~> 3.5"},

      # Erlang Distribution
      {:syn, "~> 3.4"},

      # Event Streaming
      {:gnat, "~> 1.14"},
      {:brod, "~> 4.5"},
      {:amqp, "~> 4.1"},
      {:redix, "~> 1.5"},
      # Source build instead of Hex so emqtt's rebar.config.script runs on our
      # compile and honors BUILD_WITHOUT_QUIC=1 (set in the Dockerfiles). Hex
      # flattens dynamic deps at publish time, so the Hex package always lists
      # `quicer` as non-optional even though the script would exclude it locally.
      {:emqtt, github: "emqx/emqtt", tag: "1.15.0"},
      {:ex_aws, "~> 2.6"},
      {:ex_aws_sns, "~> 2.3"},
      {:sweet_xml, "~> 0.7"},
      # Google Cloud Pub/Sub auth — OAuth2 token manager + refresh. No
      # google_api_pub_sub: it's Tesla-bound; we hit the v1 REST API directly
      # with Req instead, since publish is a single endpoint.
      {:goth, "~> 1.4"},

      # Nexmaker library
      {:nexmaker, path: "../nexmaker"}
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/edge_admin.plt"},
      plt_add_apps: [:mix, :ex_unit],
      plt_add_deps: :app_tree
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
