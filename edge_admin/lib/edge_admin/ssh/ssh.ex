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

  alias Ecto.Query.CastError
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo
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
  Creates an SSH username with optional public keys in a transaction.

  ## Parameters
  - `node` - The node struct (validated in controller via path param)
  - `params` - Request params (validated through CreateSshUsernameForm)

  ## Returns
  - `{:ok, ssh_username}` - SSH username created successfully with keys loaded
  - `{:error, changeset}` - Validation or creation failed
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

      {verified, auth_method} = check_credential(ssh_username, password, public_key)

      :telemetry.execute(
        [:edge_admin, :ssh, :verification],
        %{count: 1},
        %{result: if(verified, do: :success, else: :failure), auth_method: auth_method}
      )

      {:ok, verified}
    end
  end

  defp check_credential(nil, _password, _public_key), do: {false, :unknown}

  defp check_credential(%SshUsername{password_hash: nil}, password, _) when not is_nil(password), do: {false, :password}

  defp check_credential(%SshUsername{password_hash: hash}, password, _) when not is_nil(password),
    do: {Argon2.verify_pass(password, hash), :password}

  defp check_credential(%SshUsername{ssh_public_keys: []}, _, public_key) when not is_nil(public_key),
    do: {false, :public_key}

  defp check_credential(%SshUsername{ssh_public_keys: keys}, _, public_key) when not is_nil(public_key) do
    provided_key_normalized = normalize_ssh_key(public_key)

    result =
      Enum.any?(keys, fn stored_key ->
        stored_key_normalized = stored_key.public_key |> String.trim() |> normalize_ssh_key()
        provided_key_normalized == stored_key_normalized
      end)

    {result, :public_key}
  end

  # Normalizes SSH key by removing comment (keeps algorithm + key data only)
  defp normalize_ssh_key(key_string) do
    case String.split(key_string, " ", parts: 3) do
      [algorithm, key_data, _comment] -> "#{algorithm} #{key_data}"
      [algorithm, key_data] -> "#{algorithm} #{key_data}"
      _ -> String.trim(key_string)
    end
  end

  @doc """
  Lists SSH usernames with filtering, sorting, and pagination.

  Supports filtering by:
  - `username` - Text search with wildcard support
  - `node_id` - Exact match on node ID
  - `has_password` - Boolean (filters by password_hash presence)
  - `cluster_name` - Text search with wildcard support (requires join through node)
  - `inserted_at__gte/lte` - Date range filter

  ## Returns
  - `{:ok, {ssh_usernames, meta}}` - List of SSH usernames with Flop.Meta pagination info
  - `{:error, meta}` - Validation errors (when replace_invalid_params: false)
  """
  @spec list_ssh_usernames(map()) :: {:ok, {[SshUsername.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_ssh_usernames(params \\ %{}) do
    # Parse params into Flop format
    flop_params = EdgeAdmin.RequestParser.parse(params)

    # Extract has_password filter (virtual field, handle separately)
    {has_password_filters, other_filters} =
      Enum.split_with(flop_params[:filters] || [], fn filter ->
        filter.field == :has_password
      end)

    # Extract cluster_name filters (join-based, handle separately)
    {cluster_name_filters, other_filters} =
      Enum.split_with(other_filters, fn filter ->
        filter.field == :cluster_name
      end)

    # Build base query with node→cluster join for cluster_name filtering
    base_query =
      from(u in SshUsername,
        join: n in assoc(u, :node),
        join: c in assoc(n, :cluster),
        preload: [:ssh_public_keys]
      )

    # Apply has_password filter if present
    query_with_password_filter =
      if has_password_filters == [] do
        base_query
      else
        apply_has_password_filters(base_query, has_password_filters)
      end

    # Apply cluster_name filter if present
    query_with_cluster_filter =
      if cluster_name_filters == [] do
        query_with_password_filter
      else
        apply_ssh_username_cluster_name_filters(query_with_password_filter, cluster_name_filters)
      end

    {ilike_filters, flop_params} =
      EdgeAdmin.RequestParser.split_ilike_filters(
        Map.put(flop_params, :filters, other_filters),
        [:username]
      )

    query_with_ilike =
      Enum.reduce(ilike_filters, query_with_cluster_filter, fn %{field: field, value: value}, acc ->
        from(u in acc, where: ilike(field(u, ^field), ^value))
      end)

    # Run Flop query
    case Flop.validate_and_run(query_with_ilike, flop_params,
           for: SshUsername,
           replace_invalid_params: true
         ) do
      {:ok, {usernames, meta}} ->
        {:ok, {usernames, meta}}

      {:error, meta} ->
        {:error, meta}
    end
  end

  # Apply has_password filters using WHERE clause on password_hash
  defp apply_has_password_filters(query, filters) do
    Enum.reduce(filters, query, fn filter, acc_query ->
      apply_has_password_filter(acc_query, filter)
    end)
  end

  defp apply_has_password_filter(query, %{op: :==, value: "true"}) do
    from(u in query, where: not is_nil(u.password_hash))
  end

  defp apply_has_password_filter(query, %{op: :==, value: "false"}) do
    from(u in query, where: is_nil(u.password_hash))
  end

  defp apply_has_password_filter(query, %{op: :==, value: true}) do
    from(u in query, where: not is_nil(u.password_hash))
  end

  defp apply_has_password_filter(query, %{op: :==, value: false}) do
    from(u in query, where: is_nil(u.password_hash))
  end

  defp apply_has_password_filter(query, _), do: query

  defp apply_ssh_username_cluster_name_filters(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_ssh_username_cluster_name_filter(acc, filter) end)
  end

  defp apply_ssh_username_cluster_name_filter(query, %{op: :==, value: value}) when is_binary(value) do
    from([_u, _n, c] in query, where: c.name == ^value)
  end

  defp apply_ssh_username_cluster_name_filter(query, %{op: :ilike, value: value}) when is_binary(value) do
    from([_u, _n, c] in query, where: ilike(c.name, ^value))
  end

  defp apply_ssh_username_cluster_name_filter(query, _), do: query

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
  - `ssh_username_id` - Exact match on SSH username ID
  - `node_id` - Exact match on node ID (requires join through ssh_username)
  - `username` - Text search with wildcard support (requires join through ssh_username)
  - `cluster_name` - Text search with wildcard support (requires join through ssh_username → node)
  - `inserted_at__gte/lte` - Date range filter

  ## Returns
  - `{:ok, {ssh_public_keys, meta}}` - List of SSH public keys with Flop.Meta pagination info
  - `{:error, meta}` - Validation errors (when replace_invalid_params: false)
  """
  @spec list_ssh_public_keys(map()) :: {:ok, {[SshPublicKey.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_ssh_public_keys(params \\ %{}) do
    # Parse params into Flop format
    flop_params = EdgeAdmin.RequestParser.parse(params)

    # Extract join-based custom filters
    {node_id_filters, other_filters} =
      Enum.split_with(flop_params[:filters] || [], fn filter -> filter.field == :node_id end)

    {username_filters, other_filters} =
      Enum.split_with(other_filters, fn filter -> filter.field == :username end)

    {cluster_name_filters, other_filters} =
      Enum.split_with(other_filters, fn filter -> filter.field == :cluster_name end)

    {ilike_filters, flop_params} =
      EdgeAdmin.RequestParser.split_ilike_filters(
        Map.put(flop_params, :filters, other_filters),
        [:key_name, :public_key]
      )

    # Build base query with ssh_username → node → cluster join
    base_query =
      from(k in SshPublicKey,
        join: u in assoc(k, :ssh_username),
        join: n in assoc(u, :node),
        join: c in assoc(n, :cluster)
      )

    base_query =
      base_query
      |> apply_public_key_node_id_filters(node_id_filters)
      |> apply_public_key_username_filters(username_filters)
      |> apply_public_key_cluster_name_filters(cluster_name_filters)

    base_query =
      Enum.reduce(ilike_filters, base_query, fn %{field: field, value: value}, acc ->
        from(k in acc, where: ilike(field(k, ^field), ^value))
      end)

    case Flop.validate_and_run(base_query, flop_params,
           for: SshPublicKey,
           replace_invalid_params: true
         ) do
      {:ok, {public_keys, meta}} ->
        {:ok, {public_keys, meta}}

      {:error, meta} ->
        {:error, meta}
    end
  end

  defp apply_public_key_node_id_filters(query, []), do: query

  defp apply_public_key_node_id_filters(query, filters) do
    Enum.reduce(filters, query, fn
      %{op: :==, value: value}, acc when is_binary(value) ->
        from([_k, _u, n] in acc, where: n.id == ^value)

      _filter, acc ->
        acc
    end)
  end

  defp apply_public_key_username_filters(query, []), do: query

  defp apply_public_key_username_filters(query, filters) do
    Enum.reduce(filters, query, fn
      %{op: :==, value: value}, acc when is_binary(value) ->
        from([_k, u] in acc, where: u.username == ^value)

      %{op: :ilike, value: value}, acc when is_binary(value) ->
        from([_k, u] in acc, where: ilike(u.username, ^value))

      _filter, acc ->
        acc
    end)
  end

  defp apply_public_key_cluster_name_filters(query, []), do: query

  defp apply_public_key_cluster_name_filters(query, filters) do
    Enum.reduce(filters, query, fn
      %{op: :==, value: value}, acc when is_binary(value) ->
        from([_k, _u, _n, c] in acc, where: c.name == ^value)

      %{op: :ilike, value: value}, acc when is_binary(value) ->
        from([_k, _u, _n, c] in acc, where: ilike(c.name, ^value))

      _filter, acc ->
        acc
    end)
  end
end
