# edge_admin/lib/edge_admin_web/live/membership_dashboard.ex
defmodule EdgeAdminWeb.Live.MembershipDashboard do
  @moduledoc """
  LiveDashboard page for admin cluster membership and edge cluster ownership.

  Surfaces in-BEAM coordination state that Prometheus/Grafana cannot see:
  the `:syn` topology, the weak leader, edge cluster ownership, and any
  orphaned clusters that exceed total admin capacity.

  Reads route through `:erpc.call/4` to the node currently selected in the
  LiveDashboard node switcher, so each admin can be inspected independently —
  this is the value of the page during a netsplit, when topologies diverge.
  """

  use Phoenix.LiveDashboard.PageBuilder

  @rpc_timeout 5_000

  @impl true
  def menu_link(_, _) do
    {:ok, "Admin Membership"}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    case fetch_snapshot(assigns.page.node) do
      {:ok, data} ->
        my_clusters = Map.get(data.edge_clusters, data.admin.name, %{})

        assigns =
          assign(assigns,
            admin: data.admin,
            admin_cluster: data.admin_cluster,
            edge_clusters: data.edge_clusters,
            orphaned: data.orphaned,
            my_clusters: my_clusters,
            weak_leader?: data.weak_leader?,
            error: nil
          )

        render_page(assigns)

      {:error, reason} ->
        assigns = assign(assigns, error: reason, viewing_node: assigns.page.node)
        render_error(assigns)
    end
  end

  defp render_error(assigns) do
    ~H"""
    <div class="alert alert-danger" role="alert">
      <strong>Failed to read membership state from {@viewing_node}:</strong>
      <code>{inspect(@error)}</code>
    </div>
    """
  end

  defp render_page(assigns) do
    ~H"""
    <div class="membership-page">
      <style>
        .membership-page code {
          background-color: #FEE2E2;
          color: #991B1B;
          padding: 0.15em 0.4em;
          border-radius: 3px;
          font-size: 0.875em;
        }
        .membership-page .badge {
          font-weight: 600;
          padding: 0.35em 0.6em;
        }
        .membership-page .badge.bg-success {
          background-color: #DCFCE7 !important;
          color: #166534 !important;
        }
        .membership-page .badge.bg-danger {
          background-color: #FEE2E2 !important;
          color: #991B1B !important;
        }
        .membership-page .badge.bg-warning {
          background-color: #FEF9C3 !important;
          color: #854D0E !important;
        }
        .membership-page .badge.bg-primary {
          background-color: #CFFAFE !important;
          color: #155E75 !important;
        }
        .membership-page .badge.bg-secondary {
          background-color: #F1F5F9 !important;
          color: #475569 !important;
        }
      </style>

    <h5 class="mb-3">Admin Membership</h5>

    <!-- This admin -->
    <div class="row mb-4">
      <div class="col-md-6">
        <div class="card">
          <div class="card-header">
            <h6 class="mb-0">This Admin</h6>
          </div>
          <div class="card-body">
            <table class="table table-sm mb-0">
              <tbody>
                <tr><th>Name</th><td>{@admin.name}</td></tr>
                <tr><th>Admin ID</th><td><code>{@admin.id}</code></td></tr>
                <tr><th>Erlang Node</th><td><code>{@admin.erlang_node_name}</code></td></tr>
                <tr><th>VPN Hostname</th><td>{@admin.vpn_hostname}</td></tr>
                <tr><th>Max Capacity</th><td>{@admin.max_capacity} nodes</td></tr>
                <tr>
                  <th>Weak Leader?</th>
                  <td>
                    <%= if @weak_leader? do %>
                      <span class="badge bg-success">Yes</span>
                    <% else %>
                      <span class="badge bg-secondary">No</span>
                    <% end %>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div class="col-md-6">
        <div class="card">
          <div class="card-header">
            <h6 class="mb-0">Admin Cluster: {@admin_cluster.name}</h6>
          </div>
          <div class="card-body">
            <table class="table table-sm mb-0">
              <tbody>
                <tr><th>Total Admins</th><td>{@admin_cluster.total_admins}</td></tr>
                <tr><th>Total Capacity</th><td>{@admin_cluster.total_capacity} nodes</td></tr>
                <tr><th>Total Nodes</th><td>{@admin_cluster.total_nodes}</td></tr>
                <tr>
                  <th>Capacity</th>
                  <td>
                    <%= if @admin_cluster.degraded do %>
                      <span class="badge bg-danger">Degraded — over capacity</span>
                    <% else %>
                      <span class="badge bg-success">Healthy</span>
                    <% end %>
                  </td>
                </tr>
                <tr><th>Current Weak Leader</th><td><code>{@admin_cluster.weak_leader}</code></td></tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>

    <!-- Topology -->
    <div class="row mb-4">
      <div class="col-12">
        <div class="card">
          <div class="card-header">
            <h6 class="mb-0">Topology — Connected Peers ({length(@admin_cluster.topology)})</h6>
          </div>
          <div class="card-body">
            <%= if @admin_cluster.topology == [] do %>
              <p class="text-muted mb-0">No peers in topology.</p>
            <% else %>
              <table class="table table-sm mb-0">
                <thead>
                  <tr>
                    <th>Name</th>
                    <th>Erlang Node</th>
                    <th>VPN Hostname</th>
                    <th>Max Capacity</th>
                    <th>Owned Clusters</th>
                    <th>Owned Nodes</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for peer <- Enum.sort_by(@admin_cluster.topology, & &1.name) do %>
                    <tr>
                      <td>
                        {peer.name}
                        <%= if peer.name == @admin.name do %>
                          <span class="badge bg-primary">self</span>
                        <% end %>
                        <%= if peer.name == @admin_cluster.weak_leader do %>
                          <span class="badge bg-success">weak leader</span>
                        <% end %>
                      </td>
                      <td><code>{peer.erlang_node_name}</code></td>
                      <td>{peer.vpn_hostname}</td>
                      <td>{peer.max_capacity}</td>
                      <td>{owned_cluster_count(@edge_clusters, peer.name)}</td>
                      <td>{owned_node_count(@edge_clusters, peer.name)}</td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>
        </div>
      </div>
    </div>

    <!-- This admin's owned clusters -->
    <div class="row mb-4">
      <div class="col-12">
        <div class="card">
          <div class="card-header">
            <h6 class="mb-0">Owned by This Admin ({map_size(@my_clusters)})</h6>
          </div>
          <div class="card-body">
            <%= if map_size(@my_clusters) == 0 do %>
              <p class="text-muted mb-0">This admin currently owns no edge clusters.</p>
            <% else %>
              <table class="table table-sm mb-0">
                <thead>
                  <tr>
                    <th>Cluster</th>
                    <th>Node Count</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for {cluster_name, nodes} <- Enum.sort(@my_clusters) do %>
                    <tr>
                      <td>{cluster_name}</td>
                      <td>{length(nodes)}</td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>
        </div>
      </div>
    </div>

    <!-- Orphaned clusters -->
    <div class="row">
      <div class="col-12">
        <div class="card">
          <div class="card-header">
            <h6 class="mb-0">
              Orphaned Clusters ({map_size(@orphaned)})
              <%= if map_size(@orphaned) > 0 do %>
                <span class="badge bg-warning text-dark ms-2">no admin can take these</span>
              <% end %>
            </h6>
          </div>
          <div class="card-body">
            <%= if map_size(@orphaned) == 0 do %>
              <p class="text-muted mb-0">No orphaned clusters — every cluster has an owner.</p>
            <% else %>
              <table class="table table-sm mb-0">
                <thead>
                  <tr>
                    <th>Cluster</th>
                    <th>Node Count</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for {cluster_name, nodes} <- Enum.sort(@orphaned) do %>
                    <tr>
                      <td>{cluster_name}</td>
                      <td>{length(nodes)}</td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    </div>
    """
  end

  @impl true
  def handle_refresh(socket) do
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # RPC fan-out — reads ETS on the selected node, not the local node
  # ---------------------------------------------------------------------------

  defp fetch_snapshot(node) do
    :erpc.call(node, __MODULE__, :remote_snapshot, [], @rpc_timeout)
  rescue
    e -> {:error, Exception.message(e)}
  catch
    kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
  end

  @doc false
  # Called via :erpc on the selected node. Reads ETS — must run on that node.
  def remote_snapshot do
    alias EdgeAdmin.Admins.Metadata

    {:ok,
     %{
       admin: Metadata.get_admin(),
       admin_cluster: Metadata.get_admin_cluster(),
       edge_clusters: Metadata.get_edge_clusters(),
       orphaned: Metadata.get_orphaned_clusters(),
       weak_leader?: Metadata.am_i_weak_leader?()
     }}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp owned_cluster_count(edge_clusters, admin_name) do
    edge_clusters |> Map.get(admin_name, %{}) |> map_size()
  end

  defp owned_node_count(edge_clusters, admin_name) do
    edge_clusters
    |> Map.get(admin_name, %{})
    |> Enum.reduce(0, fn {_cluster, nodes}, acc -> acc + length(nodes) end)
  end
end
