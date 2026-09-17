# edge_admin/lib/edge_admin_mcp/tools/ingress_tunneling/list_tunnel_clients.ex
defmodule EdgeAdminMcp.Tools.IngressTunneling.ListTunnelClients do
  @moduledoc """
  List Admin-managed Tunnel Client identities with pagination and timestamp
  filtering. Private keys are never returned.

  `sort` accepts comma-separated `inserted_at` and `updated_at` fields; prefix
  a field with `-` for descending order.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.IngressTunneling
  alias EdgeAdmin.IngressTunneling.Views.TunnelClientView
  alias EdgeAdminMcp.FlopParams

  @impl true
  def title, do: "List Tunnel Clients"

  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
    field :page, :integer, default: 1, min: 1
    field :page_size, :integer, default: 20, min: 1
    field :inserted_at_gte, :string
    field :inserted_at_lte, :string
    field :updated_at_gte, :string
    field :updated_at_lte, :string
    field :sort, :string, regex: EdgeAdmin.Sort.regex()
  end

  @impl true
  def execute(params, frame) do
    params
    |> FlopParams.build()
    |> IngressTunneling.list_tunnel_clients()
    |> case do
      {:ok, {tunnel_clients, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(tunnel_clients, meta, &TunnelClientView.render/1)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
