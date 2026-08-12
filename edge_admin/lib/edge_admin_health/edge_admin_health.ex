# edge_admin/lib/edge_admin_health/edge_admin_health.ex
defmodule EdgeAdminHealth do
  @moduledoc """
  Full Admin readiness checks.

  Verifies that the critical runtime services have initialized:
  - Database connection
  - Admin-cluster membership
  - Metadata computation
  - Edge VPN API reachability
  - Edge VPN CLI connection to admin cluster network
  - Proxy servers
  - Event broker connection (no-op when EVENT_BROKER_ENABLED=false)
  """

  require Logger

  @health_check_error_code 503

  # The list is fixed at module load time — `Plug.Router`'s `init_opts:`
  # snapshots it before `runtime.exs` has set :event_broker_enabled, so a
  # conditional list would freeze in the wrong state. The Event Broker check
  # below already short-circuits to `:ok` when the broker is disabled
  # (see `EdgeAdmin.Events.Broker.healthy?/0`), so always-include is safe.
  @doc "Returns the checks used by the Admin readiness and health endpoints."
  @spec checks() :: [map()]
  def checks do
    [
      %PlugCheckup.Check{name: "Database", module: __MODULE__, function: :database_health},
      %PlugCheckup.Check{name: "Membership", module: __MODULE__, function: :membership_health},
      %PlugCheckup.Check{name: "Metadata", module: __MODULE__, function: :metadata_health},
      %PlugCheckup.Check{name: "Edge VPN API", module: __MODULE__, function: :edge_vpn_api_health},
      %PlugCheckup.Check{name: "Edge VPN CLI", module: __MODULE__, function: :edge_vpn_cli_health},
      %PlugCheckup.Check{name: "Proxy Servers", module: __MODULE__, function: :proxy_servers_health},
      %PlugCheckup.Check{name: "Event Broker", module: __MODULE__, function: :event_broker_health}
    ]
  end

  @doc "Returns the HTTP error code used when an Admin health check fails."
  @spec error_code() :: pos_integer()
  def error_code, do: @health_check_error_code

  @doc "Checks whether the Admin database is responding to a simple query."
  @spec database_health() :: :ok | {:error, String.t()}
  def database_health do
    case EdgeAdmin.Repo.query("SELECT 1", []) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "Database query failed: #{inspect(reason)}"}
    end
  end

  @doc "Checks whether Admin-cluster membership has initialized."
  @spec membership_health() :: :ok | {:error, String.t()}
  def membership_health do
    if EdgeAdmin.Admins.Membership.initialized?() do
      :ok
    else
      {:error, "Membership not initialized"}
    end
  end

  @doc "Checks whether Admin metadata computation has initialized."
  @spec metadata_health() :: :ok | {:error, String.t()}
  def metadata_health do
    if EdgeAdmin.Admins.Metadata.initialized?() do
      :ok
    else
      {:error, "Metadata not initialized"}
    end
  end

  @doc "Checks reachability of the Edge VPN API with bounded retries."
  @spec edge_vpn_api_health() :: :ok | {:error, String.t()}
  def edge_vpn_api_health do
    case EdgeAdmin.Vpn.netmaker_health_check(retries: 2, retry_delay: 200) do
      :ok ->
        :ok

      {:error, :service_unavailable} ->
        Logger.debug("Edge VPN API health check failed after retries")
        {:error, "API unreachable"}
    end
  rescue
    e ->
      Logger.error("Edge VPN API health check exception: #{inspect(e)}")
      {:error, "API check exception"}
  end

  @doc "Checks that the Admin Edge VPN CLI is connected to its Admin cluster network."
  @spec edge_vpn_cli_health() :: :ok | {:error, String.t()}
  def edge_vpn_cli_health do
    admin_cluster = EdgeAdmin.Vpn.admin_cluster_name()

    case EdgeAdmin.Vpn.edge_vpn_cli_health_check() do
      {:ok, :healthy, info} ->
        if admin_cluster in info[:networks] do
          :ok
        else
          Logger.error("Not on admin cluster (#{admin_cluster}), networks: #{inspect(info[:networks])}")
          {:error, "Not on admin cluster"}
        end

      {:ok, :degraded, _info} ->
        # WireGuard interface is down — regardless of what nodes.json says, we cannot
        # route traffic. This is the critical signal for a network-partitioned admin
        # that has been cleaned up: MQTT auth will fail, WireGuard tears down, but
        # nodes.json may still list the cluster until the daemon restarts.
        Logger.error("Edge VPN CLI WireGuard interface is down")
        {:error, "WireGuard interface down"}

      {:ok, :unhealthy, _info} ->
        {:error, "Not connected to any network"}
    end
  rescue
    e ->
      Logger.error("Edge VPN CLI health check exception: #{inspect(e)}")
      {:error, "Health check exception"}
  end

  @doc "Checks whether the Admin proxy servers have initialized."
  @spec proxy_servers_health() :: :ok | {:error, String.t()}
  def proxy_servers_health do
    if EdgeAdmin.ProxyServers.initialized?() do
      :ok
    else
      {:error, "Proxy servers not initialized"}
    end
  end

  @doc "Checks the configured event broker, or returns healthy when it is disabled."
  @spec event_broker_health() :: :ok | {:error, String.t()}
  def event_broker_health do
    EdgeAdmin.Events.Broker.healthy?()
  end
end
