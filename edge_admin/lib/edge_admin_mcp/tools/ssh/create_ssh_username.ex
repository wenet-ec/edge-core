# edge_admin/lib/edge_admin_mcp/tools/ssh/create_ssh_username.ex
defmodule EdgeAdminMcp.Tools.Ssh.CreateSshUsername do
  @moduledoc """
  Create an SSH username for a node. Optionally set a password and/or public keys.

  - `node_id` — required. The node this username can SSH into.
  - `username` — required. 3–32 characters, must start with a letter or
    underscore, lowercase letters / digits / hyphens / underscores only.
  - `password` — optional. 12–128 characters. Hashed with Argon2 at rest.
    Omit for key-only auth.
  - `public_keys` — optional list of `%{key_name, public_key}`. Both fields
    are required on each entry. `public_key` must be valid OpenSSH format
    (supported algorithms: `ssh-ed25519`, `ecdsa-sha2-nistp256/384/521`,
    `ssh-rsa`). `key_name` is a human-readable label, unique within this
    username.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Naming
  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Ssh
  alias EdgeAdmin.Ssh.Schemas.SshUsername

  @username_min_length Naming.ssh_username_min_length()
  @username_max_length Naming.ssh_username_max_length()
  @username_regex Naming.ssh_username_regex()
  @public_key_regex Naming.ssh_public_key_regex()

  @impl true
  def title, do: "Create SSH Username"
  @impl true
  def annotations, do: %{"destructiveHint" => false, "idempotentHint" => false, "openWorldHint" => false}

  schema do
    field :node_id, {:required, :string}

    field :username, {:required, :string},
      min_length: @username_min_length,
      max_length: @username_max_length,
      regex: @username_regex

    field :password, :string, min_length: 12, max_length: 128

    embeds_many :public_keys do
      field :key_name, {:required, :string}, min_length: 1, max_length: 255

      field :public_key, {:required, :string}, min_length: 1, regex: @public_key_regex
    end
  end

  @impl true
  def execute(params, frame) do
    case Nodes.get_node(params.node_id) do
      {:ok, node} ->
        attrs =
          %{"username" => params.username}
          |> put_if("password", params[:password])
          |> put_if("public_keys", params[:public_keys])

        case Ssh.create_ssh_username_with_keys(node, attrs) do
          {:ok, username} ->
            {:reply, Response.json(Response.tool(), SshUsername.to_public(username)), frame}

          {:error, reason} ->
            {:reply, error_response(reason), frame}
        end

      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Node #{params.node_id} not found"), frame}
    end
  end
end
