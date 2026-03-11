# edge_admin/lib/edge_admin/mcp/tools/self_updates/self_update_requests.ex
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

defmodule EdgeAdmin.MCP.Tools.SelfUpdates.GetSelfUpdateRequest do
  @moduledoc "Get a self-update request by ID."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.SelfUpdates

  schema do
    field :request_id, :string, required: true
  end

  @impl true
  def execute(%{request_id: id}, frame) do
    case SelfUpdates.get_self_update_request(id) do
      {:ok, r} ->
        {:reply,
         Response.json(Response.tool(), %{
           id: r.id,
           status: r.status,
           targeting: r.targeting,
           summary: r.summary,
           inserted_at: r.inserted_at
         }), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Self-update request #{id} not found"), frame}
    end
  end
end

defmodule EdgeAdmin.MCP.Tools.SelfUpdates.CreateSelfUpdateRequest do
  @moduledoc """
  Trigger an agent self-update across the fleet.

  Only healthy nodes with self_update_enabled=true will be updated.

  targeting examples:
  - `{"type": "all"}` — all eligible nodes
  - `{"type": "nodes", "node_ids": ["<uuid>", ...]}` — specific nodes
  - `{"type": "clusters", "cluster_names": ["prod", ...]}` — all nodes in clusters
  """
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.SelfUpdates

  schema do
    field :targeting, :map, required: true
  end

  @impl true
  def execute(params, frame) do
    case SelfUpdates.create_self_update_request(%{"targeting" => params.targeting}) do
      {:ok, r} ->
        {:reply,
         Response.json(Response.tool(), %{
           id: r.id,
           status: r.status,
           targeting: r.targeting,
           inserted_at: r.inserted_at
         }), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to create self-update request: #{inspect(reason)}"), frame}
    end
  end
end

defmodule EdgeAdmin.MCP.Tools.SelfUpdates.DeleteSelfUpdateRequest do
  @moduledoc "Delete a self-update request. Only completed requests can be deleted."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.SelfUpdates

  schema do
    field :request_id, :string, required: true
  end

  @impl true
  def execute(%{request_id: id}, frame) do
    with {:ok, request} <- SelfUpdates.get_self_update_request(id),
         {:ok, _} <- SelfUpdates.delete_self_update_request(request) do
      {:reply, Response.text(Response.tool(), "Self-update request #{id} deleted"), frame}
    else
      {:error, :not_found} -> {:reply, Response.error(Response.tool(), "Self-update request #{id} not found"), frame}
      {:error, reason} -> {:reply, Response.error(Response.tool(), "Delete failed: #{inspect(reason)}"), frame}
    end
  end
end
