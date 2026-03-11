# edge_admin/lib/edge_admin/mcp/tools/nodes/enrollment_keys.ex
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

defmodule EdgeAdmin.MCP.Tools.Nodes.GetEnrollmentKey do
  @moduledoc "Get an enrollment key by ID."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :enrollment_key_id, :string, required: true
  end

  @impl true
  def execute(%{enrollment_key_id: id}, frame) do
    case Nodes.get_enrollment_key(id) do
      {:ok, k} ->
        {:reply,
         Response.json(Response.tool(), %{
           id: k.id,
           key: k.key,
           cluster_name: k.cluster && k.cluster.name,
           uses_remaining: k.uses_remaining,
           expired_at: k.expired_at,
           last_used_at: k.last_used_at,
           inserted_at: k.inserted_at
         }), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Enrollment key #{id} not found"), frame}
    end
  end
end

defmodule EdgeAdmin.MCP.Tools.Nodes.CreateEnrollmentKey do
  @moduledoc "Create an enrollment key for a cluster. Agents use this key to join the VPN mesh."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :cluster_name, :string, required: true
    field :uses_remaining, :integer
    field :expired_at, :string
  end

  @impl true
  def execute(params, frame) do
    case Nodes.get_cluster(params.cluster_name) do
      {:ok, cluster} ->
        attrs =
          %{} |> maybe_put("uses_remaining", params[:uses_remaining]) |> maybe_put("expired_at", params[:expired_at])

        case Nodes.create_enrollment_key(cluster, attrs) do
          {:ok, k} ->
            {:reply,
             Response.json(Response.tool(), %{
               id: k.id,
               key: k.key,
               cluster_name: params.cluster_name,
               uses_remaining: k.uses_remaining,
               expired_at: k.expired_at,
               inserted_at: k.inserted_at
             }), frame}

          {:error, reason} ->
            {:reply, Response.error(Response.tool(), "Failed to create enrollment key: #{inspect(reason)}"), frame}
        end

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Cluster #{params.cluster_name} not found"), frame}
    end
  end

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end

defmodule EdgeAdmin.MCP.Tools.Nodes.UpdateEnrollmentKey do
  @moduledoc "Update an enrollment key's uses_remaining or expired_at. Pass null to clear a field."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :enrollment_key_id, :string, required: true
    field :uses_remaining, :integer
    field :expired_at, :string
  end

  @impl true
  def execute(params, frame) do
    case Nodes.get_enrollment_key(params.enrollment_key_id) do
      {:ok, key} ->
        attrs =
          %{} |> maybe_put("uses_remaining", params[:uses_remaining]) |> maybe_put("expired_at", params[:expired_at])

        case Nodes.update_enrollment_key(key, attrs) do
          {:ok, k} ->
            {:reply,
             Response.json(Response.tool(), %{
               id: k.id,
               key: k.key,
               uses_remaining: k.uses_remaining,
               expired_at: k.expired_at,
               last_used_at: k.last_used_at
             }), frame}

          {:error, reason} ->
            {:reply, Response.error(Response.tool(), "Update failed: #{inspect(reason)}"), frame}
        end

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Enrollment key #{params.enrollment_key_id} not found"), frame}
    end
  end

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end

defmodule EdgeAdmin.MCP.Tools.Nodes.DeleteEnrollmentKey do
  @moduledoc "Delete an enrollment key. Agents that haven't enrolled yet will no longer be able to use it."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :enrollment_key_id, :string, required: true
  end

  @impl true
  def execute(%{enrollment_key_id: id}, frame) do
    with {:ok, key} <- Nodes.get_enrollment_key(id),
         {:ok, _} <- Nodes.delete_enrollment_key(key) do
      {:reply, Response.text(Response.tool(), "Enrollment key #{id} deleted"), frame}
    else
      {:error, :not_found} -> {:reply, Response.error(Response.tool(), "Enrollment key #{id} not found"), frame}
      {:error, reason} -> {:reply, Response.error(Response.tool(), "Delete failed: #{inspect(reason)}"), frame}
    end
  end
end
