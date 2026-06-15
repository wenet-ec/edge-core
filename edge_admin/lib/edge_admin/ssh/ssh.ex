# edge_admin/lib/edge_admin/ssh/ssh.ex
defmodule EdgeAdmin.Ssh do
  @moduledoc """
  SSH credential management for edge nodes.

  This module manages SSH access to edge nodes by maintaining username and public key records.
  Agents use this to verify authentication attempts and allow/deny SSH connections.

  ## Key Concepts

  - **SSH Username**: A Linux username allowed to SSH into a node
  - **SSH Public Key**: An authorized SSH public key for a username
  - **Password Authentication**: Argon2-hashed passwords for username/password SSH login
  - **Public Key Authentication**: Verification against stored public keys
  - **Credential Verification**: Agent calls to validate SSH login attempts

  ## Architecture

  - **Node-Scoped**: Each username belongs to a specific node
  - **Multiple Auth Methods**: Supports password and/or public key authentication
  - **Secure Storage**: Passwords are Argon2-hashed, never stored in plaintext
  - **Agent-Driven**: Agents call API to verify credentials during SSH login attempts

  ## Examples

      # Create SSH username with public keys
      iex> create_ssh_username_with_keys(node, %{
      ...>   "username" => "deploy",
      ...>   "public_keys" => [%{"key_name" => "laptop", "public_key" => "ssh-rsa..."}]
      ...> })
      {:ok, %SshUsername{username: "deploy", ssh_public_keys: [...]}}

      # Verify credentials (from agent)
      iex> verify_ssh_credentials(node_id, %{"username" => "deploy", "public_key" => "ssh-rsa..."})
      {:ok, true}

      # List usernames for a node
      iex> list_ssh_usernames(%{"node_id" => node_id})
      {:ok, {[%SshUsername{}, ...], %Flop.Meta{}}}
  """

  import Ecto.Query, warn: false
  import EdgeAdmin.Query, only: [case_insensitive_like: 2]

  alias Ecto.Query.CastError
  alias EdgeAdmin.Events
  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo
  alias EdgeAdmin.Ssh.CredentialMatcher
  alias EdgeAdmin.Ssh.Filters.SshPublicKeyFilters
  alias EdgeAdmin.Ssh.Filters.SshUsernameFilters
  alias EdgeAdmin.Ssh.Forms
  alias EdgeAdmin.Ssh.Schemas.SshPublicKey
  alias EdgeAdmin.Ssh.Schemas.SshUsername

  # ===========================================================================
  # SSH Username functions
  # ===========================================================================

  @doc """
  Gets a single SSH username by ID.

  ## Returns
  - `{:ok, ssh_username}` - SSH username found with public keys preloaded
  - `{:error, :not_found}` - SSH username does not exist or invalid UUID format
  """
  @spec get_ssh_username(String.t()) :: {:ok, SshUsername.t()} | {:error, :not_found}
  def get_ssh_username(id) do
    case Repo.get(SshUsername, id) do
      nil -> {:error, :not_found}
      ssh_username -> {:ok, Repo.preload(ssh_username, :ssh_public_keys)}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @doc """
  Creates an SSH username.
  """
  def create_ssh_username(attrs \\ %{}) do
    %SshUsername{}
    |> SshUsername.changeset(attrs)
    |> Repo.insert()
    |> Repo.normalize_conflict([:username])
  end

  @doc """
  Creates an SSH username and inserts each public key in sequence.

  Inserts are NOT wrapped in a database transaction. If a public-key insert
  fails after the username has been created (or after some keys succeeded),
  earlier rows are left in place — the caller gets `{:error, reason}` for the
  first failing key but no rollback runs. If atomic semantics are required,
  wrap the call in `Ecto.Multi` or delete the partial rows yourself.

  ## Parameters
  - `node` - The node struct (validated in controller via path param)
  - `params` - Request params (validated through CreateSshUsernameForm)

  ## Returns
  - `{:ok, ssh_username}` - SSH username and all keys created successfully
  - `{:error, changeset}` - Validation or creation failed (may have committed
    partial state — see caveat above)
  """
  @spec create_ssh_username_with_keys(Node.t(), map()) ::
          {:ok, SshUsername.t()} | {:error, Ecto.Changeset.t()} | {:error, {:conflict, String.t()}}
  def create_ssh_username_with_keys(%Node{} = node, params) do
    with {:ok, attrs} <- Forms.CreateSshUsernameForm.changeset(params) do
      # Extract public_keys (if present) and prepare username attrs
      {public_keys_attrs, username_attrs} = Map.pop(attrs, "public_keys", [])

      # Hash password if provided
      username_attrs =
        case Map.get(username_attrs, "password") do
          nil ->
            username_attrs

          password when is_binary(password) ->
            username_attrs
            |> Map.delete("password")
            |> Map.put("password_hash", Argon2.hash_pwd_salt(password))
        end

      username_attrs = Map.put(username_attrs, "node_id", node.id)

      # Create username
      case create_ssh_username(username_attrs) do
        {:ok, username} ->
          # Create public keys (already validated by CreateSshUsernameForm)
          key_results =
            Enum.map(public_keys_attrs, fn key_attrs ->
              key_attrs = Map.put(key_attrs, "ssh_username_id", username.id)
              insert_ssh_public_key(key_attrs)
            end)

          case Enum.find(key_results, &match?({:error, _}, &1)) do
            nil ->
              keys = Enum.map(key_results, fn {:ok, key} -> key end)
              {:ok, %{username | ssh_public_keys: keys}}

            {:error, reason} ->
              {:error, reason}
          end

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Deletes an SSH username.
  """
  def delete_ssh_username(%SshUsername{} = ssh_username) do
    Repo.delete(ssh_username)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking SSH username changes.
  """
  def change_ssh_username(%SshUsername{} = ssh_username, attrs \\ %{}) do
    SshUsername.changeset(ssh_username, attrs)
  end

  @doc """
  Verifies SSH credentials (password or public key) for a given node and username.

  Used by agents to validate SSH authentication attempts. Does not distinguish
  between "username not found" and "incorrect credential" for security reasons.

  Every call (success or failure) emits the `[:edge_admin, :ssh, :verification]`
  telemetry event and publishes a `Catalog.SshUsernameVerified` event with the
  attempted username, auth method, and result — this is the audit trail for
  SSH access attempts and is the primary signal for security alerting.

  ## Parameters
  - `node_id` - The node ID (from agent's API token)
  - `params` - Request params containing username and either password or public_key

  ## Returns
  - `{:ok, true}` - Credential verified successfully
  - `{:ok, false}` - Username not found or credential incorrect
  - `{:error, changeset}` - Validation failed
  """
  @spec verify_ssh_credentials(String.t(), map()) :: {:ok, boolean()} | {:error, Ecto.Changeset.t()}
  def verify_ssh_credentials(node_id, params) do
    with {:ok, attrs} <- Forms.VerifySshCredentialsForm.changeset(params) do
      username = Map.get(attrs, "username")
      password = Map.get(attrs, "password")
      public_key = Map.get(attrs, "public_key")

      # Query SSH username for this node (with preloaded public keys)
      ssh_username =
        case list_ssh_usernames(%{"node_id" => node_id, "username" => username, "page_size" => "1"}) do
          {:ok, {[ssh_username | _], _meta}} -> ssh_username
          {:ok, {[], _meta}} -> nil
          {:error, _meta} -> nil
        end

      {verified, auth_method} = CredentialMatcher.check(ssh_username, password, public_key)
      result = if verified, do: :success, else: :failure

      :telemetry.execute(
        [:edge_admin, :ssh, :verification],
        %{count: 1},
        %{result: result, auth_method: auth_method}
      )

      Events.publish(%Catalog.SshUsernameVerified{
        ssh_username: ssh_username && Repo.preload(ssh_username, node: :cluster),
        node_id: node_id,
        attempted_username: username,
        auth_method: auth_method,
        result: result
      })

      {:ok, verified}
    end
  end

  @doc """
  Lists SSH usernames with filtering, sorting, and pagination.

  Supports filtering by:
  - `username` - Text search with wildcard support
  - `node_ids` - Exact IN match on node IDs (comma-separated on REST, array on MCP)
  - `has_password` - Boolean (filters by password_hash presence)
  - `cluster_name` - Text search with wildcard support (requires join through node)
  - `cluster_names` - Exact IN match on cluster names (comma-separated on REST, array on MCP)
  - `key_name` - Text search with wildcard support on associated public key names (joins ssh_public_keys)
  - `key_names` - Exact IN match on associated public key names (comma-separated on REST, array on MCP)
  - `inserted_at__gte/lte` - Date range filter

  ## Returns
  - `{:ok, {ssh_usernames, meta}}` - List of SSH usernames with Flop.Meta pagination info
  - `{:error, meta}` - Validation errors (when replace_invalid_params: false)
  """
  @spec list_ssh_usernames(map()) :: {:ok, {[SshUsername.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_ssh_usernames(params \\ %{}) do
    flop_params = EdgeAdmin.RequestParser.parse(params)
    {custom, ilike_filters, flop_params} = split_username_filters(flop_params)

    base_query =
      from(u in SshUsername,
        join: n in assoc(u, :node),
        join: c in assoc(n, :cluster),
        preload: [:ssh_public_keys]
      )

    query =
      base_query
      |> SshUsernameFilters.apply_has_password(custom.has_password)
      |> SshUsernameFilters.apply_cluster_name(custom.cluster_name)
      |> SshUsernameFilters.apply_cluster_name(custom.cluster_names)
      |> SshUsernameFilters.apply_node_ids(custom.node_ids)
      |> SshUsernameFilters.apply_key_name(custom.key_name)
      |> SshUsernameFilters.apply_key_name(custom.key_names)

    query =
      Enum.reduce(ilike_filters, query, fn %{field: field, value: value}, acc ->
        from(u in acc, where: case_insensitive_like(field(u, ^field), ^value))
      end)

    case Flop.validate_and_run(query, flop_params,
           for: SshUsername,
           replace_invalid_params: true
         ) do
      {:ok, {usernames, meta}} -> {:ok, {usernames, meta}}
      {:error, meta} -> {:error, meta}
    end
  end

  defp split_username_filters(flop_params) do
    custom_fields = [:has_password, :cluster_name, :cluster_names, :node_ids, :key_name, :key_names]

    {custom_filters, rest} =
      Enum.split_with(flop_params[:filters] || [], fn f -> f.field in custom_fields end)

    custom = Map.new(custom_fields, fn field -> {field, Enum.filter(custom_filters, &(&1.field == field))} end)

    {ilike_filters, flop_params} =
      EdgeAdmin.RequestParser.split_ilike_filters(Map.put(flop_params, :filters, rest), [:username])

    {custom, ilike_filters, flop_params}
  end

  # ===========================================================================
  # SSH Public Key functions
  # ===========================================================================

  @doc """
  Gets a single SSH public key by ID.

  ## Returns
  - `{:ok, ssh_public_key}` - SSH public key found
  - `{:error, :not_found}` - SSH public key does not exist or invalid UUID format
  """
  def get_ssh_public_key(id) do
    case Repo.get(SshPublicKey, id) do
      nil -> {:error, :not_found}
      ssh_public_key -> {:ok, ssh_public_key}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @doc """
  Creates an SSH public key.

  ## Parameters
  - `ssh_username` - The SSH username struct (validated in controller via path param)
  - `params` - Request params (validated through CreateSshPublicKeyForm)

  ## Returns
  - `{:ok, ssh_public_key}` - SSH public key created successfully
  - `{:error, changeset}` - Validation or creation failed
  """
  @spec create_ssh_public_key(SshUsername.t(), map()) ::
          {:ok, SshPublicKey.t()} | {:error, Ecto.Changeset.t()} | {:error, {:conflict, String.t()}}
  def create_ssh_public_key(%SshUsername{} = ssh_username, params) do
    with {:ok, attrs} <- Forms.CreateSshPublicKeyForm.changeset(params) do
      attrs = Map.put(attrs, "ssh_username_id", ssh_username.id)
      insert_ssh_public_key(attrs)
    end
  end

  # Private function for internal use (bypasses form validation when attrs already validated)
  defp insert_ssh_public_key(attrs) do
    %SshPublicKey{}
    |> SshPublicKey.changeset(attrs)
    |> Repo.insert()
    |> Repo.normalize_conflict([:key_name])
  end

  @doc """
  Updates an SSH public key.
  """
  def update_ssh_public_key(%SshPublicKey{} = ssh_public_key, attrs) do
    ssh_public_key
    |> SshPublicKey.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an SSH public key.
  """
  def delete_ssh_public_key(%SshPublicKey{} = ssh_public_key) do
    Repo.delete(ssh_public_key)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking SSH public key changes.
  """
  def change_ssh_public_key(%SshPublicKey{} = ssh_public_key, attrs \\ %{}) do
    SshPublicKey.changeset(ssh_public_key, attrs)
  end

  @doc """
  Lists SSH public keys with filtering, sorting, and pagination.

  Supports filtering by:
  - `key_name` - Text search with wildcard support
  - `public_key` - Text search with wildcard support (useful for searching email comments)
  - `ssh_username_ids` - Exact IN match on SSH username IDs (comma-separated on REST, array on MCP)
  - `node_ids` - Exact IN match on node IDs (requires join through ssh_username)
  - `username` - Text search with wildcard support (requires join through ssh_username)
  - `usernames` - Exact IN match on SSH usernames (comma-separated on REST, array on MCP)
  - `cluster_name` - Text search with wildcard support (requires join through ssh_username → node)
  - `cluster_names` - Exact IN match on cluster names (comma-separated on REST, array on MCP)
  - `inserted_at__gte/lte` - Date range filter

  ## Returns
  - `{:ok, {ssh_public_keys, meta}}` - List of SSH public keys with Flop.Meta pagination info
  - `{:error, meta}` - Validation errors (when replace_invalid_params: false)
  """
  @spec list_ssh_public_keys(map()) :: {:ok, {[SshPublicKey.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_ssh_public_keys(params \\ %{}) do
    flop_params = EdgeAdmin.RequestParser.parse(params)
    {custom, ilike_filters, flop_params} = split_public_key_filters(flop_params)

    base_query =
      from(k in SshPublicKey,
        join: u in assoc(k, :ssh_username),
        join: n in assoc(u, :node),
        join: c in assoc(n, :cluster)
      )

    query =
      base_query
      |> SshPublicKeyFilters.apply_ssh_username_ids(custom.ssh_username_ids)
      |> SshPublicKeyFilters.apply_node_id(custom.node_ids)
      |> SshPublicKeyFilters.apply_username(custom.username)
      |> SshPublicKeyFilters.apply_username(custom.usernames)
      |> SshPublicKeyFilters.apply_cluster_name(custom.cluster_name)
      |> SshPublicKeyFilters.apply_cluster_name(custom.cluster_names)

    query =
      Enum.reduce(ilike_filters, query, fn %{field: field, value: value}, acc ->
        from(k in acc, where: case_insensitive_like(field(k, ^field), ^value))
      end)

    case Flop.validate_and_run(query, flop_params,
           for: SshPublicKey,
           replace_invalid_params: true
         ) do
      {:ok, {public_keys, meta}} -> {:ok, {public_keys, meta}}
      {:error, meta} -> {:error, meta}
    end
  end

  defp split_public_key_filters(flop_params) do
    custom_fields = [:ssh_username_ids, :node_ids, :username, :usernames, :cluster_name, :cluster_names]

    {custom_filters, rest} =
      Enum.split_with(flop_params[:filters] || [], fn f -> f.field in custom_fields end)

    custom = Map.new(custom_fields, fn field -> {field, Enum.filter(custom_filters, &(&1.field == field))} end)

    {ilike_filters, flop_params} =
      EdgeAdmin.RequestParser.split_ilike_filters(Map.put(flop_params, :filters, rest), [:key_name, :public_key])

    {custom, ilike_filters, flop_params}
  end
end
