# edge_admin/lib/edge_admin_mcp/tools/ssh/create_ssh_public_key.ex
defmodule EdgeAdminMcp.Tools.Ssh.CreateSshPublicKey do
  @moduledoc """
  Add an SSH public key to an existing SSH username.

  - `public_key` — required. Valid OpenSSH format: `<algorithm> <base64> [comment]`.
    Supported algorithms: `ssh-ed25519` (recommended), `ecdsa-sha2-nistp256`,
    `ecdsa-sha2-nistp384`, `ecdsa-sha2-nistp521`, `ssh-rsa`.
  - `key_name` — required. Human-readable label, 1–255 characters. Must be
    unique within the parent SSH username.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Naming
  alias EdgeAdmin.Ssh

  @public_key_regex Naming.ssh_public_key_regex()

  @impl true
  def title, do: "Create SSH Public Key"
  @impl true
  def annotations, do: %{"destructiveHint" => false, "idempotentHint" => false, "openWorldHint" => false}

  schema do
    field :ssh_username_id, {:required, :string}
    field :public_key, {:required, :string}, min_length: 1, regex: @public_key_regex
    field :key_name, {:required, :string}, min_length: 1, max_length: 255
  end

  @impl true
  def execute(params, frame) do
    case Ssh.get_ssh_username(params.ssh_username_id) do
      {:ok, ssh_username} ->
        attrs = %{"public_key" => params.public_key, "key_name" => params.key_name}

        case Ssh.create_ssh_public_key(ssh_username, attrs) do
          {:ok, key} ->
            {:reply, Response.json(Response.tool(), key), frame}

          {:error, reason} ->
            {:reply, error_response(reason), frame}
        end

      {:error, :not_found} ->
        {:reply, error_response(:not_found, "SSH username #{params.ssh_username_id} not found"), frame}
    end
  end
end
