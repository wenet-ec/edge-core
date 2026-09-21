# edge_admin/lib/edge_admin_mcp/tools/ingress_tunneling/create_tunnel_connection.ex
defmodule EdgeAdminMcp.Tools.IngressTunneling.CreateTunnelConnection do
  @moduledoc "Create a Tunnel Connection for an existing Tunnel Client."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.IngressTunneling
  alias EdgeAdmin.IngressTunneling.Views.TunnelConnectionView

  @impl true
  def title, do: "Create Tunnel Connection"
  @impl true
  def annotations, do: %{"destructiveHint" => false, "idempotentHint" => false, "openWorldHint" => false}

  schema do
    field :tunnel_client_id, {:required, :string}
    field :node_id, {:required, :string}
  end

  @impl true
  def execute(%{tunnel_client_id: client_id, node_id: node_id}, frame) do
    case IngressTunneling.create_tunnel_connection(client_id, %{"node_id" => node_id}) do
      {:ok, connection} -> {:reply, Response.json(Response.tool(), TunnelConnectionView.render(connection)), frame}
      {:error, reason} -> {:reply, error_response(reason), frame}
    end
  end
end
