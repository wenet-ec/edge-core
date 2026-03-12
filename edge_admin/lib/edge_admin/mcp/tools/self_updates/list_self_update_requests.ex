# edge_admin/lib/edge_admin/mcp/tools/self_updates/list_self_update_requests.ex
defmodule EdgeAdmin.MCP.Tools.SelfUpdates.ListSelfUpdateRequests do
  @moduledoc "List self-update requests. These trigger agent container updates across the fleet."
  use EdgeAdmin.MCP, :tool

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
           self_update_requests: Enum.map(requests, &format/1),
           total: meta.total_count,
           page: meta.current_page
         }), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to list self-update requests: #{inspect(reason)}"), frame}
    end
  end

  defp format(r),
    do: %{id: r.id, status: r.status, targeting: r.targeting, summary: r.summary, inserted_at: r.inserted_at}

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
