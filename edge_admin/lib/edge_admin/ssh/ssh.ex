# edge_admin/lib/edge_admin/ssh/ssh.ex
defmodule EdgeAdmin.Ssh do
  @moduledoc """
  Canonical API for SSH usernames, public keys, and credential verification.

  Persistence is delegated to the `SshUsernames` and `SshPublicKeys` resources;
  authentication is delegated to the explicit `Credentials` workflow.
  """

  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Ssh.Resources.Credentials
  alias EdgeAdmin.Ssh.Resources.SshPublicKeys
  alias EdgeAdmin.Ssh.Resources.SshUsernames
  alias EdgeAdmin.Ssh.Schemas.SshPublicKey
  alias EdgeAdmin.Ssh.Schemas.SshUsername

  @doc "Gets an SSH username by ID, preloading its public keys."
  @spec get_ssh_username(String.t()) :: {:ok, SshUsername.t()} | {:error, :not_found}
  defdelegate get_ssh_username(id), to: SshUsernames, as: :get

  @doc "Preloads public keys for an SSH username."
  @spec preload_ssh_public_keys(SshUsername.t()) :: SshUsername.t()
  defdelegate preload_ssh_public_keys(username), to: SshUsernames, as: :preload_public_keys

  @doc "Creates an SSH username from validated attributes."
  @spec create_ssh_username(map()) :: {:ok, SshUsername.t()} | {:error, Ecto.Changeset.t()}
  defdelegate create_ssh_username(attrs \\ %{}), to: SshUsernames, as: :create

  @doc "Deletes an SSH username."
  @spec delete_ssh_username(SshUsername.t()) :: {:ok, SshUsername.t()} | {:error, Ecto.Changeset.t()}
  defdelegate delete_ssh_username(username), to: SshUsernames, as: :delete

  @doc "Builds an SSH username changeset for form rendering."
  @spec change_ssh_username(SshUsername.t(), map()) :: Ecto.Changeset.t()
  defdelegate change_ssh_username(username, attrs \\ %{}), to: SshUsernames, as: :change

  @doc "Lists SSH usernames with filtering, sorting, and pagination."
  @spec list_ssh_usernames(map()) :: {:ok, {[SshUsername.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  defdelegate list_ssh_usernames(params \\ %{}), to: SshUsernames, as: :list

  @doc "Verifies a password or public-key SSH credential for a node."
  @spec verify_ssh_credentials(String.t(), map()) :: {:ok, boolean()} | {:error, Ecto.Changeset.t()}
  defdelegate verify_ssh_credentials(node_id, params), to: Credentials, as: :verify

  @doc "Gets an SSH public key by ID."
  @spec get_ssh_public_key(String.t()) :: {:ok, SshPublicKey.t()} | {:error, :not_found}
  defdelegate get_ssh_public_key(id), to: SshPublicKeys, as: :get

  @doc "Updates an SSH public key."
  @spec update_ssh_public_key(SshPublicKey.t(), map()) :: {:ok, SshPublicKey.t()} | {:error, Ecto.Changeset.t()}
  defdelegate update_ssh_public_key(key, attrs), to: SshPublicKeys, as: :update

  @doc "Deletes an SSH public key."
  @spec delete_ssh_public_key(SshPublicKey.t()) :: {:ok, SshPublicKey.t()} | {:error, Ecto.Changeset.t()}
  defdelegate delete_ssh_public_key(key), to: SshPublicKeys, as: :delete

  @doc "Builds an SSH public-key changeset for form rendering."
  @spec change_ssh_public_key(SshPublicKey.t(), map()) :: Ecto.Changeset.t()
  defdelegate change_ssh_public_key(key, attrs \\ %{}), to: SshPublicKeys, as: :change

  @doc "Lists SSH public keys with filtering, sorting, and pagination."
  @spec list_ssh_public_keys(map()) :: {:ok, {[SshPublicKey.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  defdelegate list_ssh_public_keys(params \\ %{}), to: SshPublicKeys, as: :list

  @doc "Creates an SSH username and its nested public keys."
  @spec create_ssh_username_with_keys(Node.t(), map()) ::
          {:ok, SshUsername.t()} | {:error, Ecto.Changeset.t()} | {:error, {:conflict, String.t()}}
  def create_ssh_username_with_keys(%Node{} = node, params), do: SshUsernames.create_with_keys(node, params)

  @doc "Creates an SSH public key for an existing username."
  @spec create_ssh_public_key(SshUsername.t(), map()) ::
          {:ok, SshPublicKey.t()} | {:error, Ecto.Changeset.t()} | {:error, {:conflict, String.t()}}
  def create_ssh_public_key(%SshUsername{} = username, params), do: SshPublicKeys.create(username, params)
end
