# edge_admin/lib/edge_admin/mcp/tools/self_updates/list_self_update_requests.ex
defmodule EdgeAdmin.MCP.Tools.SelfUpdates.ListSelfUpdateRequests do
  @moduledoc "List self-update requests. These trigger agent container updates across the fleet."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.MCP.Tools.SelfUpdates.SelfUpdateRequestData
  alias EdgeAdmin.SelfUpdates

  schema do
    field :page, :integer, default: 1
    field :page_size, :integer, default: 20
    field :status, :string
  end

  @impl true
  def execute(params, frame) do
    query =
      maybe_put(%{"page" => params[:page] || 1, "page_size" => params[:page_size] || 20}, "status", params[:status])

    case SelfUpdates.list_self_update_requests(query) do
      {:ok, {requests, meta}} ->
        {:reply,
         Response.json(Response.tool(), %{
           data: Enum.map(requests, &SelfUpdateRequestData.data/1),
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
        {:reply, Response.error(Response.tool(), "Failed to list self-update requests: #{inspect(reason)}"), frame}
    end
  end

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
