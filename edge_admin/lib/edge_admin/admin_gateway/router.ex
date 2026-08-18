# edge_admin/lib/edge_admin/admin_gateway/router.ex
defmodule EdgeAdmin.AdminGateway.Router do
  @moduledoc """
  Resolves clusters to the Admin Gateway responsible for them.

  This is the routing boundary for Admin Gateway callers. The current runtime
  uses the Gateway process directly; the lookup details remain contained here.
  """

  alias EdgeAdmin.AdminClustering.Metadata
  alias EdgeAdmin.AdminGateway.Worker
  alias EdgeAdminProxy.AdminTunnel.Client, as: AdminTunnelClient
  alias EdgeAdminProxy.Config, as: ProxyConfig

  @spec resolve(String.t()) :: {:ok, pid()} | {:error, :no_owner | :gateway_not_found}
  def resolve(cluster_name) when is_binary(cluster_name) do
    Worker.lookup(cluster_name)
  end

  @spec resolve_node(struct()) ::
          {:ok, pid()} | {:error, :no_owner | :gateway_not_found | :cluster_not_loaded}
  def resolve_node(%{cluster: %{name: cluster_name}}) when is_binary(cluster_name), do: resolve(cluster_name)

  def resolve_node(_node), do: {:error, :cluster_not_loaded}

  @spec open_stream(String.t(), String.t(), 1..65_535) ::
          {:ok, :gen_tcp.socket()} | {:error, term()}
  def open_stream(cluster_name, target_host, target_port) do
    with owner when is_binary(owner) <- Metadata.get_cluster_owner(cluster_name),
         {:ok, _gateway_pid} <- Worker.lookup(cluster_name) do
      if owner == Application.get_env(:edge_admin, :admin_name) do
        connect_local_target(target_host, target_port)
      else
        with {:ok, admin_hostname} <- owner_hostname(owner) do
          AdminTunnelClient.connect(admin_hostname, target_host, target_port)
        end
      end
    else
      nil -> {:error, :no_owner}
    end
  end

  defp owner_hostname(owner_name) do
    case Enum.find(Metadata.get_peer_admins(), &(&1.name == owner_name)) do
      %{vpn_hostname: hostname} when is_binary(hostname) -> {:ok, hostname}
      _ -> {:error, :gateway_not_found}
    end
  end

  defp connect_local_target(target_host, target_port) do
    :gen_tcp.connect(
      String.to_charlist(target_host),
      target_port,
      [:binary, packet: :raw, active: false],
      ProxyConfig.connection_timeout()
    )
  end
end
