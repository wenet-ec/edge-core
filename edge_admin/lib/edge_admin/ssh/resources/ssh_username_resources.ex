# edge_admin/lib/edge_admin/ssh/resources/ssh_username_resources.ex
defmodule EdgeAdmin.Ssh.Resources.SshUsernameResources do
  @moduledoc false

  import Ecto.Query, warn: false
  import EdgeAdmin.Query, only: [case_insensitive_like: 2]

  alias Ecto.Query.CastError
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.PasswordHashers
  alias EdgeAdmin.Repo
  alias EdgeAdmin.Ssh.Filters.SshUsernameFilters
  alias EdgeAdmin.Ssh.Forms
  alias EdgeAdmin.Ssh.Resources.SshPublicKeyResources
  alias EdgeAdmin.Ssh.Schemas.SshUsername

  @doc "Gets an SSH username by ID, preloading its public keys."
  @spec get(String.t()) :: {:ok, SshUsername.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(SshUsername, id) do
      nil -> {:error, :not_found}
      username -> {:ok, Repo.preload(username, :ssh_public_keys)}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @spec create(map()) ::
          {:ok, SshUsername.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, {:conflict, String.t()}}
  def create(attrs),
    do: %SshUsername{} |> SshUsername.changeset(attrs) |> Repo.insert() |> Repo.normalize_conflict([:username])

  @doc "Creates an SSH username and its nested public keys atomically."
  @spec create_with_keys(Node.t(), map()) ::
          {:ok, SshUsername.t()} | {:error, Ecto.Changeset.t()} | {:error, {:conflict, String.t()}}
  def create_with_keys(%Node{} = node, params) do
    with {:ok, attrs} <- Forms.CreateSshUsernameForm.changeset(params) do
      {keys_attrs, username_attrs} = Map.pop(attrs, "public_keys", [])

      username_attrs =
        case Map.pop(username_attrs, "password") do
          {nil, attrs} -> attrs
          {password, attrs} -> Map.put(attrs, "password_hash", PasswordHashers.hash(password))
        end

      Repo.transaction_with_write_lock(fn ->
        with {:ok, username} <- create(Map.put(username_attrs, "node_id", node.id)),
             {:ok, keys} <- create_public_keys(username.id, keys_attrs) do
          %{username | ssh_public_keys: keys}
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  def delete(%SshUsername{} = username), do: Repo.delete(username)

  defp create_public_keys(ssh_username_id, keys_attrs) do
    keys_attrs
    |> Enum.reduce_while({:ok, []}, fn attrs, {:ok, keys} ->
      case SshPublicKeyResources.create(Map.put(attrs, "ssh_username_id", ssh_username_id)) do
        {:ok, key} -> {:cont, {:ok, [key | keys]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, keys} -> {:ok, Enum.reverse(keys)}
      error -> error
    end
  end

  @doc "Lists SSH usernames with filtering, sorting, and pagination."
  @spec list(map()) :: {:ok, {[SshUsername.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list(params \\ %{}) do
    flop_params = EdgeAdmin.RequestParser.parse(params)
    {custom, ilike, flop_params} = split_filters(flop_params)

    query =
      from(u in SshUsername, join: n in assoc(u, :node), join: c in assoc(n, :cluster), preload: [:ssh_public_keys])
      |> SshUsernameFilters.apply_has_password(custom.has_password)
      |> SshUsernameFilters.apply_cluster_name(custom.cluster_name)
      |> SshUsernameFilters.apply_node_ids(custom.node_id)
      |> SshUsernameFilters.apply_key_name(custom.key_name)

    query =
      Enum.reduce(ilike, query, fn %{field: field, value: value}, acc ->
        from(u in acc, where: case_insensitive_like(field(u, ^field), ^value))
      end)

    Flop.validate_and_run(query, flop_params, for: SshUsername, replace_invalid_params: true)
  end

  defp split_filters(params) do
    fields = [:has_password, :cluster_name, :node_id, :key_name]
    {custom, rest} = Enum.split_with(params[:filters] || [], &(&1.field in fields))
    custom = Map.new(fields, &{&1, Enum.filter(custom, fn f -> f.field == &1 end)})
    {ilike, params} = EdgeAdmin.RequestParser.split_ilike_filters(Map.put(params, :filters, rest), [:username])
    {custom, ilike, params}
  end
end
