# edge_admin/lib/edge_admin/ssh/ssh.ex
defmodule EdgeAdmin.Ssh do
  @moduledoc """
  Canonical API for SSH usernames, public keys, and credential verification.

  The context coordinates persistence and credential verification for SSH
  accounts and keys.
  """

  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Ssh.Credentials.Verification
  alias EdgeAdmin.Ssh.Resources.SshPublicKeyResources
  alias EdgeAdmin.Ssh.Resources.SshUsernameResources
  alias EdgeAdmin.Ssh.Schemas.SshPublicKey
  alias EdgeAdmin.Ssh.Schemas.SshUsername

  @doc "Gets an SSH username by ID, preloading its public keys."
  @spec get_ssh_username(String.t()) :: {:ok, SshUsername.t()} | {:error, :not_found}
  defdelegate get_ssh_username(id), to: SshUsernameResources, as: :get

  @spec delete_ssh_username(SshUsername.t()) :: {:ok, SshUsername.t()} | {:error, Ecto.Changeset.t()}
  defdelegate delete_ssh_username(username), to: SshUsernameResources, as: :delete

  @doc "Lists SSH usernames with filtering, sorting, and pagination."
  @spec list_ssh_usernames(map()) :: {:ok, {[SshUsername.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  defdelegate list_ssh_usernames(params \\ %{}), to: SshUsernameResources, as: :list

  @doc "Verifies a password or public-key SSH credential for a node."
  @spec verify_ssh_credentials(String.t(), map()) :: {:ok, boolean()} | {:error, Ecto.Changeset.t()}
  defdelegate verify_ssh_credentials(node_id, params), to: Verification, as: :verify

  @spec get_ssh_public_key(String.t()) :: {:ok, SshPublicKey.t()} | {:error, :not_found}
  defdelegate get_ssh_public_key(id), to: SshPublicKeyResources, as: :get

  @spec delete_ssh_public_key(SshPublicKey.t()) :: {:ok, SshPublicKey.t()} | {:error, Ecto.Changeset.t()}
  defdelegate delete_ssh_public_key(key), to: SshPublicKeyResources, as: :delete

  @doc "Lists SSH public keys with filtering, sorting, and pagination."
  @spec list_ssh_public_keys(map()) :: {:ok, {[SshPublicKey.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  defdelegate list_ssh_public_keys(params \\ %{}), to: SshPublicKeyResources, as: :list

  @doc "Creates an SSH username and its nested public keys atomically."
  @spec create_ssh_username_with_keys(Node.t(), map()) ::
          {:ok, SshUsername.t()} | {:error, Ecto.Changeset.t()} | {:error, {:conflict, String.t()}}
  def create_ssh_username_with_keys(%Node{} = node, params) do
    SshUsernameResources.create_with_keys(node, params)
  end

  @doc "Creates an SSH public key for an existing username."
  @spec create_ssh_public_key(SshUsername.t(), map()) ::
          {:ok, SshPublicKey.t()} | {:error, Ecto.Changeset.t()} | {:error, {:conflict, String.t()}}
  def create_ssh_public_key(%SshUsername{} = username, params) do
    SshPublicKeyResources.create_for_username(username, params)
  end
end
