# edge_admin/lib/edge_admin/mcp/tools/ssh/list_ssh_public_keys.ex
defmodule EdgeAdmin.MCP.Tools.Ssh.ListSshPublicKeys do
  @moduledoc "List SSH public keys. Filter by ssh_username_id to scope to a specific user."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.MCP.Tools.Ssh.SshPublicKeyData
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
           data: Enum.map(keys, &SshPublicKeyData.data/1),
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
        {:reply, Response.error(Response.tool(), "Failed to list SSH public keys: #{inspect(reason)}"), frame}
    end
  end

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
