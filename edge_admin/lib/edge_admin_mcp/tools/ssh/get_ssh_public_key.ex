# edge_admin/lib/edge_admin_mcp/tools/ssh/get_ssh_public_key.ex
defmodule EdgeAdminMcp.Tools.Ssh.GetSshPublicKey do
  @moduledoc """
  Get an SSH public key by ID.

  - `ssh_public_key_id` — required. The public key to retrieve.

  The response includes the key name and public key material, along with its
  parent SSH username. Private keys are never stored or returned.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Ssh
  alias EdgeAdmin.Ssh.Views.SshPublicKeyView

  @impl true
  def title, do: "Get SSH Public Key"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
    field :ssh_public_key_id, {:required, :string}
  end

  @impl true
  def execute(%{ssh_public_key_id: id}, frame) do
    case Ssh.get_ssh_public_key(id) do
      {:ok, key} ->
        {:reply, Response.json(Response.tool(), SshPublicKeyView.render(key)), frame}

      {:error, :not_found} ->
        {:reply, error_response(:not_found, "SSH public key #{id} not found"), frame}
    end
  end
end
