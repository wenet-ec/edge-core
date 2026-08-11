# edge_admin/lib/edge_admin/ssh/resources/public_keys.ex
defmodule EdgeAdmin.Ssh.Resources.SshPublicKeys do
  @moduledoc "Persistence and queries for SSH public keys."

  import Ecto.Query, warn: false
  import EdgeAdmin.Query, only: [case_insensitive_like: 2]

  alias Ecto.Query.CastError
  alias EdgeAdmin.Repo
  alias EdgeAdmin.Ssh.Filters.SshPublicKeyFilters
  alias EdgeAdmin.Ssh.Forms
  alias EdgeAdmin.Ssh.Schemas.SshPublicKey
  alias EdgeAdmin.Ssh.Schemas.SshUsername

  @doc "Gets an SSH public key by ID."
  @spec get(String.t()) :: {:ok, SshPublicKey.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(SshPublicKey, id) do
      nil -> {:error, :not_found}
      key -> {:ok, key}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @spec create(SshUsername.t(), map()) ::
          {:ok, SshPublicKey.t()} | {:error, Ecto.Changeset.t()} | {:error, {:conflict, String.t()}}
  def create(%SshUsername{} = username, params) do
    with {:ok, attrs} <- Forms.CreateSshPublicKeyForm.changeset(params) do
      attrs |> Map.put("ssh_username_id", username.id) |> insert()
    end
  end

  @spec insert(map()) :: {:ok, SshPublicKey.t()} | {:error, Ecto.Changeset.t()} | {:error, {:conflict, String.t()}}
  def insert(attrs) do
    %SshPublicKey{}
    |> SshPublicKey.changeset(attrs)
    |> Repo.insert()
    |> Repo.normalize_conflict([:key_name])
  end

  @doc "Updates an SSH public key."
  def update(%SshPublicKey{} = key, attrs), do: key |> SshPublicKey.changeset(attrs) |> Repo.update()

  @doc "Deletes an SSH public key."
  def delete(%SshPublicKey{} = key), do: Repo.delete(key)

  @doc "Builds an SSH public-key changeset."
  def change(%SshPublicKey{} = key, attrs \\ %{}), do: SshPublicKey.changeset(key, attrs)

  @spec list(map()) :: {:ok, {[SshPublicKey.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list(params \\ %{}) do
    flop_params = EdgeAdmin.RequestParser.parse(params)
    {custom, ilike_filters, flop_params} = split_filters(flop_params)

    query =
      from(k in SshPublicKey,
        join: u in assoc(k, :ssh_username),
        join: n in assoc(u, :node),
        join: c in assoc(n, :cluster)
      )
      |> SshPublicKeyFilters.apply_ssh_username_ids(custom.ssh_username_id)
      |> SshPublicKeyFilters.apply_node_id(custom.node_id)
      |> SshPublicKeyFilters.apply_username(custom.username)
      |> SshPublicKeyFilters.apply_cluster_name(custom.cluster_name)

    query =
      Enum.reduce(ilike_filters, query, fn %{field: field, value: value}, acc ->
        from(k in acc, where: case_insensitive_like(field(k, ^field), ^value))
      end)

    Flop.validate_and_run(query, flop_params, for: SshPublicKey, replace_invalid_params: true)
  end

  defp split_filters(flop_params) do
    fields = [:ssh_username_id, :node_id, :username, :cluster_name]
    {custom, rest} = Enum.split_with(flop_params[:filters] || [], &(&1.field in fields))
    custom = Map.new(fields, &{&1, Enum.filter(custom, fn f -> f.field == &1 end)})

    {ilike, params} =
      EdgeAdmin.RequestParser.split_ilike_filters(Map.put(flop_params, :filters, rest), [:key_name, :public_key])

    {custom, ilike, params}
  end
end
