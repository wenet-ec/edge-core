# edge_admin/lib/edge_admin_mcp/tools/ssh/delete_ssh_username.ex
defmodule EdgeAdminMcp.Tools.Ssh.DeleteSshUsername do
  @moduledoc "Delete an SSH username and all its associated public keys."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Ssh

  @impl true
  def title, do: "Delete SSH Username"
  @impl true
  def annotations, do: %{"destructiveHint" => true, "idempotentHint" => false, "openWorldHint" => false}

  schema do
    field :ssh_username_id, {:required, :string}
  end

  @impl true
  def execute(%{ssh_username_id: id}, frame) do
    with {:ok, username} <- Ssh.get_ssh_username(id),
         {:ok, _} <- Ssh.delete_ssh_username(username) do
      {:reply, Response.json(Response.tool(), %{deleted: true, id: id}), frame}
    else
      {:error, :not_found} ->
        {:reply, error_response(:not_found, "SSH username #{id} not found"), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
