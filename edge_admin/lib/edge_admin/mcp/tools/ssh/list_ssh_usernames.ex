# edge_admin/lib/edge_admin/mcp/tools/ssh/list_ssh_usernames.ex
defmodule EdgeAdmin.MCP.Tools.Ssh.ListSshUsernames do
  @moduledoc "List SSH usernames. Filter by node_id to see credentials for a specific node."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.MCP.Tools.Ssh.SshUsernameData
  alias EdgeAdmin.Ssh

  schema do
    field :page, :integer, default: 1
    field :page_size, :integer, default: 20
    field :node_id, :string
    field :username, :string
  end

  @impl true
  def execute(params, frame) do
    query =
      %{"page" => params[:page] || 1, "page_size" => params[:page_size] || 20}
      |> maybe_put("node_id", params[:node_id])
      |> maybe_put("username", params[:username])

    case Ssh.list_ssh_usernames(query) do
      {:ok, {usernames, meta}} ->
        {:reply,
         Response.json(Response.tool(), %{
           data: Enum.map(usernames, &SshUsernameData.data/1),
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
        {:reply, Response.error(Response.tool(), "Failed to list SSH usernames: #{inspect(reason)}"), frame}
    end
  end

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
