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
      Tailscale.ConnectionManager,
      {Oban, Application.fetch_env!(:edge_admin, Oban)},
      EdgeAdminWeb.Endpoint,
      {TelemetryUI, EdgeAdmin.TelemetryUI.config()}
    ]

    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
      config: %{metadata: [:file, :line]}
    })

    opts = [strategy: :one_for_one, name: EdgeAdmin.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        if should_run_bootstrap?() do
          case EdgeAdmin.Bootstrap.run() do
            {:ok, :bootstrap_complete} ->
              {:ok, pid}

            {:error, reason} ->
              Logger.error("Bootstrap failed: #{inspect(reason)}")
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
      :auto -> Mix.env() != :test and phoenix_server_starting?()
    end
  end

  defp phoenix_server_starting? do
    # Only run bootstrap when Phoenix server is actually starting
    System.get_env("PHX_SERVER") == "true"
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EdgeAdminWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
