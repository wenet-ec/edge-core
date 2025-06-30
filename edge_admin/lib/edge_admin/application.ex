# edge_admin/lib/edge_admin/application.ex
defmodule EdgeAdmin.Application do
  @moduledoc """
  Main entry point of the app
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      EdgeAdmin.PromEx,
      EdgeAdmin.Repo,
      {DNSCluster, query: Application.get_env(:edge_admin, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: EdgeAdmin.PubSub},
      EdgeAdmin.Tailscale.ConnectionManager,
      {Oban, Application.fetch_env!(:edge_admin, Oban)},
      EdgeAdminWeb.Endpoint,
      {TelemetryUI, EdgeAdmin.TelemetryUI.config()}
    ]

    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
      config: %{
        metadata: [:file, :line]
      }
    })

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: EdgeAdmin.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Run bootstrap if not in test environment
        if should_run_bootstrap?() do
          case EdgeAdmin.Bootstrap.run() do
            {:ok, :bootstrap_complete} ->
              {:ok, pid}

            {:error, reason} ->
              Logger.error("Bootstrap failed: #{inspect(reason)}")
              # Continue for now, but you might want {:error, reason}
              {:ok, pid}
          end
        else
          Logger.info("Skipping bootstrap in #{Mix.env()} environment")
          {:ok, pid}
        end

      error ->
        error
    end
  end

  defp should_run_bootstrap? do
    case Application.get_env(:edge_admin, :run_bootstrap, :auto) do
      false -> false
      true -> true
      :auto -> Mix.env() != :test
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EdgeAdminWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
