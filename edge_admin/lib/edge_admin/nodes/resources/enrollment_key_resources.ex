# edge_admin/lib/edge_admin/nodes/resources/enrollment_key_resources.ex
defmodule EdgeAdmin.Nodes.Resources.EnrollmentKeyResources do
  @moduledoc """
  Enrollment-key management and verification for edge-node provisioning.

  This module owns enrollment-key persistence, filtering, blob generation, and
  one-use verification. A finite-use key is consumed only after the target
  cluster has capacity and its Edge VPN enrollment key is available.
  `EdgeAdmin.Nodes` keeps a small facade for callers while the enrollment-key
  lifecycle lives here.
  """

  import Ecto.Query, warn: false
  import EdgeAdmin.Query, only: [case_insensitive_like: 2]

  alias Ecto.Query.CastError
  alias EdgeAdmin.Events
  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.Nodes.Checks
  alias EdgeAdmin.Nodes.Filters.ClusterFilters
  alias EdgeAdmin.Nodes.Filters.EnrollmentKeyFilters
  alias EdgeAdmin.Nodes.Forms
  alias EdgeAdmin.Nodes.Queries.ClusterQueries
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.EnrollmentKey
  alias EdgeAdmin.Random
  alias EdgeAdmin.Repo
  alias EdgeAdmin.RequestParser
  alias EdgeAdmin.Vpn

  @enrollment_key_custom_filters [
    cluster_name: &ClusterFilters.apply_name/2,
    is_unlimited: &EnrollmentKeyFilters.apply_is_unlimited/2,
    is_spent: &EnrollmentKeyFilters.apply_is_spent/2,
    is_expired: &EnrollmentKeyFilters.apply_is_expired/2,
    is_never_used: &EnrollmentKeyFilters.apply_is_never_used/2,
    has_expiry: &EnrollmentKeyFilters.apply_has_expiry/2,
    has_name: &EnrollmentKeyFilters.apply_has_name/2
  ]

  @doc """
  Lists enrollment keys with filtering, sorting, and pagination.
  """
  @spec list(map()) :: {:ok, {[EnrollmentKey.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list(params \\ %{}) do
    flop_params = RequestParser.parse(params)
    {query, flop_params} = build_list_query(flop_params)

    Flop.validate_and_run(query, flop_params,
      for: EnrollmentKey,
      replace_invalid_params: true
    )
  end

  @doc """
  Gets a single enrollment key by ID.
  """
  @spec get(String.t()) :: {:ok, EnrollmentKey.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(EnrollmentKey, id) do
      nil -> {:error, :not_found}
      key -> {:ok, Repo.preload(key, :cluster)}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @doc "Inserts an enrollment key from validated attributes."
  @spec create(map()) :: {:ok, EnrollmentKey.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %EnrollmentKey{}
    |> EnrollmentKey.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates an enrollment key from validated attributes."
  @spec update(EnrollmentKey.t(), map()) :: {:ok, EnrollmentKey.t()} | {:error, Ecto.Changeset.t()}
  def update(%EnrollmentKey{} = key, attrs) do
    key
    |> EnrollmentKey.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes an enrollment key from the database."
  @spec delete(EnrollmentKey.t()) :: {:ok, EnrollmentKey.t()} | {:error, Ecto.Changeset.t()}
  def delete(%EnrollmentKey{} = key), do: Repo.delete(key)

  @doc "Validates attributes, generates the enrollment blob, and creates a cluster-bound key."
  @spec create_for_cluster(Cluster.t(), map()) ::
          {:ok, EnrollmentKey.t()} | {:error, Ecto.Changeset.t()}
  def create_for_cluster(%Cluster{} = cluster, attrs) do
    with {:ok, attrs} <- Forms.CreateEnrollmentKeyForm.changeset(attrs) do
      admin_urls = Application.fetch_env!(:edge_admin, :admin_urls)
      nonce = Random.token()

      key = build_key_blob(admin_urls, cluster.name, nonce)

      key_attrs =
        attrs
        |> Map.put("key", key)
        |> Map.put("cluster_id", cluster.id)

      with {:ok, enrollment_key} <- create(key_attrs) do
        {:ok, Repo.preload(enrollment_key, :cluster)}
      end
    end
  end

  @doc false
  @spec build_key_blob([String.t()], String.t(), String.t()) :: String.t()
  def build_key_blob(admin_urls, cluster_name, nonce) do
    %{"admin_urls" => admin_urls, "cluster_name" => cluster_name, "nonce" => nonce}
    |> JSON.encode!()
    |> Base.encode64(padding: false)
  end

  @doc "Validates and updates an enrollment key's uses limit or expiry."
  @spec update_enrollment_key(EnrollmentKey.t(), map()) ::
          {:ok, EnrollmentKey.t()} | {:error, Ecto.Changeset.t()}
  def update_enrollment_key(%EnrollmentKey{} = key, params) do
    with {:ok, attrs} <- Forms.UpdateEnrollmentKeyForm.changeset(params),
         {:ok, updated_key} <- __MODULE__.update(key, attrs) do
      {:ok, Repo.preload(updated_key, :cluster)}
    end
  end

  @doc """
  Verifies an enrollment-key blob presented by an Agent before VPN enrollment.

  Verification checks the stored blob, cluster binding, expiry, remaining uses,
  and cluster capacity. It also loads the target cluster's Edge VPN enrollment
  key before consuming the Admin key. A successful finite-use key is consumed
  atomically.
  """
  @spec verify(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def verify(params) do
    with {:ok, %{"key" => key_blob}} <- Forms.VerifyEnrollmentKeyForm.changeset(params) do
      {result, enrollment_key} =
        case Repo.get_by(EnrollmentKey, key: key_blob) do
          nil ->
            {%{verified: false, error: "invalid_key", vpn_enrollment_key: "", enrollment_key_id: nil}, nil}

          enrollment_key ->
            enrollment_key = Repo.preload(enrollment_key, :cluster)
            {verify_key(enrollment_key), enrollment_key}
        end

      enqueue_verified_event(enrollment_key, result, key_blob)
      {:ok, result}
    end
  end

  defp build_list_query(flop_params) do
    custom_fields = Keyword.keys(@enrollment_key_custom_filters)

    {custom, other_filters} =
      Enum.split_with(flop_params[:filters] || [], &(&1.field in custom_fields))

    custom_by_field = Enum.group_by(custom, & &1.field)

    base_query =
      ClusterQueries.active_joined(from(k in EnrollmentKey, join: c in assoc(k, :cluster), preload: [cluster: c]))

    query = apply_custom_filters(base_query, custom_by_field)

    {ilike_filters, flop_params} =
      RequestParser.split_ilike_filters(
        Map.put(flop_params, :filters, other_filters),
        [:name, :key]
      )

    query =
      Enum.reduce(ilike_filters, query, fn %{field: field, value: value}, acc ->
        from(k in acc, where: case_insensitive_like(field(k, ^field), ^value))
      end)

    {query, flop_params}
  end

  defp apply_custom_filters(query, custom_by_field) do
    Enum.reduce(@enrollment_key_custom_filters, query, fn {field, fun}, acc ->
      EnrollmentKeyFilters.apply_maybe(acc, custom_by_field[field], fun)
    end)
  end

  defp enqueue_verified_event(enrollment_key, %{verified: verified, error: error}, key_blob) do
    Events.publish(%Catalog.EnrollmentKeyVerified{
      enrollment_key: enrollment_key,
      result: verification_result(verified, error),
      attempted_key_blob: if(is_nil(enrollment_key), do: key_blob)
    })
  end

  defp verification_result(true, _), do: :verified
  defp verification_result(false, "invalid_key"), do: :invalid_key
  defp verification_result(false, "key_expired"), do: :key_expired
  defp verification_result(false, "key_spent"), do: :key_spent
  defp verification_result(false, "node_limit_reached"), do: :node_limit_reached
  defp verification_result(false, "vpn_enrollment_key_unavailable"), do: :vpn_enrollment_key_unavailable

  defp verify_key(%EnrollmentKey{} = key) do
    cond do
      not cluster_matches?(key) -> verification_failure("invalid_key")
      EnrollmentKey.expired?(key) -> verification_failure("key_expired")
      EnrollmentKey.spent?(key) -> verification_failure("key_spent")
      true -> verify_capacity_and_consume(key)
    end
  end

  defp verify_capacity_and_consume(%EnrollmentKey{} = key) do
    case Checks.NodeLimitCheck.check(key.cluster) do
      {:error, _} ->
        verification_failure("node_limit_reached")

      :ok ->
        network_name = Cluster.network_name(key.cluster)

        case Vpn.get_default_enrollment_key(network_name) do
          {:ok, vpn_enrollment_key} when is_binary(vpn_enrollment_key) and vpn_enrollment_key != "" ->
            consume_key(key, vpn_enrollment_key)

          _ ->
            verification_failure("vpn_enrollment_key_unavailable")
        end
    end
  end

  defp verification_failure(error), do: %{verified: false, error: error, vpn_enrollment_key: "", enrollment_key_id: nil}

  defp cluster_matches?(%EnrollmentKey{key: key_blob, cluster: %Cluster{name: cluster_name}}) do
    with {:ok, json} <- Base.decode64(key_blob, padding: false),
         {:ok, %{"cluster_name" => ^cluster_name}} <- JSON.decode(json) do
      true
    else
      _ -> false
    end
  end

  defp consume_key(%EnrollmentKey{} = key, vpn_enrollment_key) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    {rows_updated, _} =
      if EnrollmentKey.unlimited?(key) do
        Repo.update_all(
          from(k in EnrollmentKey, where: k.id == ^key.id),
          set: [last_used_at: now]
        )
      else
        Repo.update_all(
          from(k in EnrollmentKey, where: k.id == ^key.id and k.uses_remaining > 0),
          inc: [uses_remaining: -1],
          set: [last_used_at: now]
        )
      end

    if rows_updated == 0 do
      verification_failure("key_spent")
    else
      %{verified: true, error: "", vpn_enrollment_key: vpn_enrollment_key, enrollment_key_id: key.id}
    end
  end
end
