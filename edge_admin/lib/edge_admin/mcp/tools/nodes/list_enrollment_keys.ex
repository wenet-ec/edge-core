# edge_admin/lib/edge_admin/mcp/tools/nodes/list_enrollment_keys.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.ListEnrollmentKeys do
  @moduledoc "List enrollment keys. Keys are used by agents to join a cluster's VPN network."
  use EdgeAdmin.MCP, :tool

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
           enrollment_keys: Enum.map(keys, &format/1),
           total: meta.total_count,
           page: meta.current_page
         }), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to list enrollment keys: #{inspect(reason)}"), frame}
    end
  end

  defp format(k),
    do: %{
      id: k.id,
      key: k.key,
      cluster_name: k.cluster && k.cluster.name,
      uses_remaining: k.uses_remaining,
      expired_at: k.expired_at,
      last_used_at: k.last_used_at,
      inserted_at: k.inserted_at
    }

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
