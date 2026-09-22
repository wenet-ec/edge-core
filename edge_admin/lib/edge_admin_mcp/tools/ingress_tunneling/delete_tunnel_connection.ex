# edge_admin/lib/edge_admin_mcp/tools/ingress_tunneling/delete_tunnel_connection.ex
defmodule EdgeAdminMcp.Tools.IngressTunneling.DeleteTunnelConnection do
  @moduledoc "Permanently delete a Tunnel Connection and release its address allocation."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.IngressTunneling

  @impl true
  def title, do: "Delete Tunnel Connection"
  @impl true
  def annotations, do: %{"destructiveHint" => true, "idempotentHint" => false, "openWorldHint" => false}

  schema do
    field :tunnel_connection_id, {:required, :string}
  end

  @impl true
  def execute(%{tunnel_connection_id: id}, frame) do
    with {:ok, connection} <- IngressTunneling.get_tunnel_connection(id),
         {:ok, _connection} <- IngressTunneling.delete_tunnel_connection(connection) do
      {:reply, Response.json(Response.tool(), %{deleted: true, id: id}), frame}
    else
      {:error, :not_found} -> {:reply, error_response(:not_found, "Tunnel Connection #{id} not found"), frame}
      {:error, reason} -> {:reply, error_response(reason), frame}
    end
  end
end
