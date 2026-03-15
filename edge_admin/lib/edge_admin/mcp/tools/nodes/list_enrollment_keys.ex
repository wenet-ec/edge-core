# edge_admin/lib/edge_admin/mcp/tools/nodes/list_enrollment_keys.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.ListEnrollmentKeys do
  @moduledoc "List enrollment keys. Keys are used by agents to join a cluster's VPN network."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.MCP.Tools.Nodes.EnrollmentKeyData
  alias EdgeAdmin.Nodes

  schema do
    field :page, :integer, default: 1
    field :page_size, :integer, default: 20
    field :cluster_name, :string
  end

  @impl true
  def execute(params, frame) do
    query =
      maybe_put(
        %{"page" => params[:page] || 1, "page_size" => params[:page_size] || 20},
        "cluster_name",
        params[:cluster_name]
      )

    case Nodes.list_enrollment_keys(query) do
      {:ok, {keys, meta}} ->
        {:reply,
         Response.json(Response.tool(), %{
           data: Enum.map(keys, &EnrollmentKeyData.data/1),
           pagination: %{
             page: meta.current_page,
             page_size: meta.page_size,
             total: meta.total_count,
             total_pages: meta.total_pages,
             has_next: meta.has_next_page?,
             has_prev: meta.has_previous_page?
           }
         }), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to list enrollment keys: #{inspect(reason)}"), frame}
    end
  end

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
