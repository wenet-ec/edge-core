# edge_admin/lib/edge_admin_mcp/tools/ingress_tunneling/list_tunnel_connections.ex
defmodule EdgeAdminMcp.Tools.IngressTunneling.ListTunnelConnections do
  @moduledoc "Lists Tunnel Client connections with pagination, filtering, and sorting."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.IngressTunneling
  alias EdgeAdmin.IngressTunneling.Views.TunnelConnectionView
  alias EdgeAdminMcp.FlopParams

  @impl true
  def title, do: "List Tunnel Connections"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
    field :page, :integer, default: 1, min: 1
    field :page_size, :integer, default: 20, min: 1
    field :tunnel_client_id_in, {:list, :string}
    field :node_id_in, {:list, :string}
    field :sort, :string, regex: EdgeAdmin.Sort.regex()
  end

  @impl true
  def execute(params, frame) do
    params
    |> FlopParams.build()
    |> IngressTunneling.list_tunnel_connections()
    |> case do
      {:ok, {connections, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(connections, meta, &TunnelConnectionView.render/1)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
