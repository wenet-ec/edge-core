# edge_admin/lib/edge_admin_mcp/tools/ingress_tunneling/get_tunnel_connection.ex
defmodule EdgeAdminMcp.Tools.IngressTunneling.GetTunnelConnection do
  @moduledoc "Get a Tunnel Connection by ID."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.IngressTunneling
  alias EdgeAdmin.IngressTunneling.Views.TunnelConnectionView

  @impl true
  def title, do: "Get Tunnel Connection"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
    field :tunnel_connection_id, {:required, :string}
  end

  @impl true
  def execute(%{tunnel_connection_id: id}, frame) do
    case IngressTunneling.get_tunnel_connection(id) do
      {:ok, connection} -> {:reply, Response.json(Response.tool(), TunnelConnectionView.render(connection)), frame}
      {:error, :not_found} -> {:reply, error_response(:not_found, "Tunnel Connection #{id} not found"), frame}
    end
  end
end
