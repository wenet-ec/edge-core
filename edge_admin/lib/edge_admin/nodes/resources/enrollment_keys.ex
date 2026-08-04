# edge_admin/lib/edge_admin/nodes/resources/enrollment_keys.ex
defmodule EdgeAdmin.Nodes.Resources.EnrollmentKeys do
  @moduledoc """
  Enrollment-key management and verification for edge-node provisioning.

  This module owns enrollment-key persistence, filtering, blob generation, and
  one-use verification. A finite-use key is consumed only after the target
  cluster has capacity and its Netmaker enrollment key is available.
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
    {query, flop_params} = build_query(flop_params)

    case Flop.validate_and_run(query, flop_params,
           for: EnrollmentKey,
           replace_invalid_params: true
         ) do
      {:ok, {keys, meta}} -> {:ok, {keys, meta}}
      {:error, meta} -> {:error, meta}
    end
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

  @doc """
  Creates an enrollment key for a cluster.

  The stored and returned value is a base64 JSON blob containing the Admin
  URLs, cluster name, and a nonce. The complete blob is later presented to the
  verification endpoint.
  """
  @spec create(Cluster.t(), map()) ::
          {:ok, EnrollmentKey.t()} | {:error, Ecto.Changeset.t()}
  def create(%Cluster{} = cluster, params \\ %{}) do
    with {:ok, attrs} <- Forms.CreateEnrollmentKeyForm.changeset(params) do
      admin_urls = Application.fetch_env!(:edge_admin, :admin_urls)
      nonce = Random.token()

      key =
        %{"admin_urls" => admin_urls, "cluster_name" => cluster.name, "nonce" => nonce}
        |> JSON.encode!()
        |> Base.encode64(padding: false)

      key_attrs =
        attrs
        |> Map.put("key", key)
        |> Map.put("cluster_id", cluster.id)

      case %EnrollmentKey{} |> EnrollmentKey.changeset(key_attrs) |> Repo.insert() do
        {:ok, enrollment_key} -> {:ok, Repo.preload(enrollment_key, :cluster)}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  @doc """
  Updates an enrollment key's uses limit or expiry.
  """
  @spec update(EnrollmentKey.t(), map()) ::
          {:ok, EnrollmentKey.t()} | {:error, Ecto.Changeset.t()}
  def update(%EnrollmentKey{} = key, params) do
    with {:ok, attrs} <- Forms.UpdateEnrollmentKeyForm.changeset(params) do
      case key |> EnrollmentKey.changeset(attrs) |> Repo.update() do
        {:ok, updated_key} -> {:ok, Repo.preload(updated_key, :cluster)}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  @doc "Deletes an enrollment key."
  @spec delete(EnrollmentKey.t()) :: {:ok, EnrollmentKey.t()} | {:error, Ecto.Changeset.t()}
  def delete(%EnrollmentKey{} = key), do: Repo.delete(key)

  @doc """
  Verifies an enrollment-key blob presented by an Agent before VPN enrollment.

  Verification checks the stored blob, cluster binding, expiry, remaining uses,
  and cluster capacity. It also loads the target cluster's Netmaker enrollment
  key before consuming the Admin key. A successful finite-use key is consumed
  atomically.
  """
  @spec verify(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def verify(params) do
    with {:ok, key_blob} <- Forms.VerifyEnrollmentKeyForm.changeset(params) do
      {result, enrollment_key} =
        case Repo.get_by(EnrollmentKey, key: key_blob) do
          nil ->
            {%{verified: false, error: "invalid_key", netmaker_key: "", enrollment_key_id: nil}, nil}

          enrollment_key ->
            enrollment_key = Repo.preload(enrollment_key, :cluster)
            {verify_key(enrollment_key), enrollment_key}
        end

      enqueue_verified_event(enrollment_key, result, key_blob)
      {:ok, result}
    end
  end

  defp build_query(flop_params) do
    custom_fields = Keyword.keys(@enrollment_key_custom_filters)

    {custom, other_filters} =
      Enum.split_with(flop_params[:filters] || [], &(&1.field in custom_fields))

    custom_by_field = Enum.group_by(custom, & &1.field)

    base_query =
      from(k in EnrollmentKey,
        join: c in assoc(k, :cluster),
        preload: [cluster: c]
      )

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
  defp verification_result(false, "netmaker_key_unavailable"), do: :netmaker_key_unavailable

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
        network_name = Vpn.build_network_name(key.cluster.name, prefix: :node)

        case Vpn.get_default_enrollment_key(network_name) do
          {:ok, netmaker_key} when is_binary(netmaker_key) and netmaker_key != "" ->
            consume_key(key, netmaker_key)

          _ ->
            verification_failure("netmaker_key_unavailable")
        end
    end
  end

  defp verification_failure(error), do: %{verified: false, error: error, netmaker_key: "", enrollment_key_id: nil}

  defp cluster_matches?(%EnrollmentKey{key: key_blob, cluster: %Cluster{name: cluster_name}}) do
    with {:ok, json} <- Base.decode64(key_blob, padding: false),
         {:ok, %{"cluster_name" => ^cluster_name}} <- JSON.decode(json) do
      true
    else
      _ -> false
    end
  end

  defp consume_key(%EnrollmentKey{} = key, netmaker_key) do
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
      %{verified: true, error: "", netmaker_key: netmaker_key, enrollment_key_id: key.id}
    end
  end
end
