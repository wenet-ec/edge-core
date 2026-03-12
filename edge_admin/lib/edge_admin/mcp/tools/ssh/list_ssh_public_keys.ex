# edge_admin/lib/edge_admin/mcp/tools/ssh/list_ssh_public_keys.ex
defmodule EdgeAdmin.MCP.Tools.Ssh.ListSshPublicKeys do
  @moduledoc "List SSH public keys. Filter by ssh_username_id to scope to a specific user."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Ssh

  schema do
    field :page, :integer, default: 1
    field :page_size, :integer, default: 20
    field :ssh_username_id, :string
    field :key_name, :string
  end

  @impl true
  def execute(params, frame) do
    query =
      %{"page" => params[:page] || 1, "page_size" => params[:page_size] || 20}
      |> maybe_put("ssh_username_id", params[:ssh_username_id])
      |> maybe_put("key_name", params[:key_name])

    case Ssh.list_ssh_public_keys(query) do
      {:ok, {keys, meta}} ->
        {:reply,
         Response.json(Response.tool(), %{
           ssh_public_keys: Enum.map(keys, &format/1),
           total: meta.total_count,
           page: meta.current_page
         }), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to list SSH public keys: #{inspect(reason)}"), frame}
    end
  end

  defp format(k),
    do: %{
      id: k.id,
      key_name: k.key_name,
      public_key: k.public_key,
      ssh_username_id: k.ssh_username_id,
      inserted_at: k.inserted_at
    }

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
