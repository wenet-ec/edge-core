# edge_admin/lib/edge_admin_mcp/tools/admins/get_admin.ex
defmodule EdgeAdminMcp.Tools.Admins.GetAdmin do
  @moduledoc """
  Get information about this admin instance — ID, name, Netmaker host
  identity, WireGuard peer capacity, and last metadata recompute time.

  Returns the per-admin record from `EdgeAdmin.Admins.Metadata` ETS:
  `id`, `name`, `max_wireguard_peers`, `admin_peer_count`,
  `edge_node_capacity`, `erlang_node_name`, `vpn_hostname`,
  `admin_cluster_name`, `netmaker_host_id`, `last_computed_at`.

  For the admin's assigned edge clusters, use `get_my_admin_cluster` —
  cluster ownership lives at the admin-cluster level, not on the per-admin
  record.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Admins.Metadata

  @impl true
  def title, do: "Get Admin Info"
  @impl true
  def annotations, do: %{"readOnlyHint" => true}

  schema do
  end

  @impl true
  def execute(_params, frame) do
    {:reply, Response.json(Response.tool(), Metadata.get_admin()), frame}
  end
end
