# edge_admin/test/edge_admin/nodes/filters/enrollment_key_filters_test.exs
defmodule EdgeAdmin.Nodes.Filters.EnrollmentKeyFiltersTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Filters.EnrollmentKeyFilters
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.EnrollmentKey
  alias EdgeAdmin.Repo

  defp insert_cluster do
    Repo.insert!(
      struct(Cluster, %{
        id: Ecto.UUID.generate(),
        name: "cluster-#{:rand.uniform(999_999)}",
        ipv4_range: "100.64.#{:rand.uniform(200)}.0/24"
      })
    )
  end

  defp insert_key(cluster_id, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          cluster_id: cluster_id,
          name: "key-#{:rand.uniform(999_999)}",
          key: "blob-#{Ecto.UUID.generate()}",
          uses_remaining: 1,
          expires_at: nil,
          last_used_at: nil
        },
        overrides
      )

    # Use Ecto.Changeset.change/2 (bypasses schema validations like
    # `uses_remaining > 0`) so we can write nil into nullable fields. A
    # plain `struct(...)` insert keeps the schema-default value for nil
    # fields instead of writing NULL — that matters here because the
    # `unlimited` and `expires_at == nil` cases need real NULLs in the row.
    %EnrollmentKey{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!()
  end

  defp ids(query), do: query |> Repo.all() |> Enum.map(& &1.id) |> Enum.sort()

  # ---------------------------------------------------------------------------
  # apply_is_unlimited/2 — uses_remaining IS [NOT] NULL
  # ---------------------------------------------------------------------------

  describe "apply_is_unlimited/2" do
    test "true matches keys with uses_remaining == nil" do
      cluster = insert_cluster()
      unlimited = insert_key(cluster.id, %{uses_remaining: nil})
      _bounded = insert_key(cluster.id, %{uses_remaining: 5})

      query =
        EnrollmentKeyFilters.apply_is_unlimited(EnrollmentKey, [%{op: :==, value: true}])

      assert ids(query) == [unlimited.id]
    end

    test "false matches keys with non-null uses_remaining" do
      cluster = insert_cluster()
      _unlimited = insert_key(cluster.id, %{uses_remaining: nil})
      bounded = insert_key(cluster.id, %{uses_remaining: 5})

      query =
        EnrollmentKeyFilters.apply_is_unlimited(EnrollmentKey, [%{op: :==, value: false}])

      assert ids(query) == [bounded.id]
    end

    test "string 'true' / 'false' are ignored" do
      cluster = insert_cluster()
      unlimited = insert_key(cluster.id, %{uses_remaining: nil})
      bounded = insert_key(cluster.id, %{uses_remaining: 5})

      assert ids(EnrollmentKeyFilters.apply_is_unlimited(EnrollmentKey, [%{op: :==, value: "true"}])) ==
               Enum.sort([unlimited.id, bounded.id])

      assert ids(EnrollmentKeyFilters.apply_is_unlimited(EnrollmentKey, [%{op: :==, value: "false"}])) ==
               Enum.sort([unlimited.id, bounded.id])
    end

    test "no filters / unrecognised filter → query unchanged" do
      cluster = insert_cluster()
      a = insert_key(cluster.id)
      b = insert_key(cluster.id)

      assert ids(EnrollmentKeyFilters.apply_is_unlimited(EnrollmentKey, [])) ==
               Enum.sort([a.id, b.id])

      assert ids(EnrollmentKeyFilters.apply_is_unlimited(EnrollmentKey, [%{op: :>=, value: 1}])) ==
               Enum.sort([a.id, b.id])
    end
  end

  # ---------------------------------------------------------------------------
  # apply_is_spent/2 — uses_remaining == 0
  # ---------------------------------------------------------------------------

  describe "apply_is_spent/2" do
    test "true matches keys with uses_remaining == 0" do
      cluster = insert_cluster()
      spent = insert_key(cluster.id, %{uses_remaining: 0})
      _live = insert_key(cluster.id, %{uses_remaining: 5})
      _unlimited = insert_key(cluster.id, %{uses_remaining: nil})

      query = EnrollmentKeyFilters.apply_is_spent(EnrollmentKey, [%{op: :==, value: true}])

      assert ids(query) == [spent.id]
    end

    test "false matches keys with uses_remaining != 0 OR nil (unlimited included)" do
      cluster = insert_cluster()
      _spent = insert_key(cluster.id, %{uses_remaining: 0})
      live = insert_key(cluster.id, %{uses_remaining: 5})
      unlimited = insert_key(cluster.id, %{uses_remaining: nil})

      query = EnrollmentKeyFilters.apply_is_spent(EnrollmentKey, [%{op: :==, value: false}])

      assert ids(query) == Enum.sort([live.id, unlimited.id])
    end
  end

  # ---------------------------------------------------------------------------
  # apply_is_expired/2 — comparison against now/0 at query time
  # ---------------------------------------------------------------------------

  describe "apply_is_expired/2" do
    test "true matches keys with expires_at in the past" do
      cluster = insert_cluster()
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      expired = insert_key(cluster.id, %{expires_at: past})
      _future = insert_key(cluster.id, %{expires_at: future})
      _no_expiry = insert_key(cluster.id, %{expires_at: nil})

      query = EnrollmentKeyFilters.apply_is_expired(EnrollmentKey, [%{op: :==, value: true}])

      assert ids(query) == [expired.id]
    end

    test "false matches keys with no expiry OR future expiry" do
      cluster = insert_cluster()
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      _expired = insert_key(cluster.id, %{expires_at: past})
      future_key = insert_key(cluster.id, %{expires_at: future})
      no_expiry = insert_key(cluster.id, %{expires_at: nil})

      query = EnrollmentKeyFilters.apply_is_expired(EnrollmentKey, [%{op: :==, value: false}])

      assert ids(query) == Enum.sort([future_key.id, no_expiry.id])
    end
  end

  # ---------------------------------------------------------------------------
  # apply_is_never_used/2 — last_used_at IS [NOT] NULL
  # ---------------------------------------------------------------------------

  describe "apply_is_never_used/2" do
    test "true matches keys with last_used_at == nil" do
      cluster = insert_cluster()
      now = DateTime.truncate(DateTime.utc_now(), :second)

      never_used = insert_key(cluster.id, %{last_used_at: nil})
      _used = insert_key(cluster.id, %{last_used_at: now})

      query =
        EnrollmentKeyFilters.apply_is_never_used(EnrollmentKey, [%{op: :==, value: true}])

      assert ids(query) == [never_used.id]
    end

    test "false matches keys that have been used at least once" do
      cluster = insert_cluster()
      now = DateTime.truncate(DateTime.utc_now(), :second)

      _never_used = insert_key(cluster.id, %{last_used_at: nil})
      used = insert_key(cluster.id, %{last_used_at: now})

      query =
        EnrollmentKeyFilters.apply_is_never_used(EnrollmentKey, [%{op: :==, value: false}])

      assert ids(query) == [used.id]
    end
  end

  # ---------------------------------------------------------------------------
  # apply_has_expiry/2 — expires_at IS [NOT] NULL (does NOT check whether the
  # timestamp is in the past)
  # ---------------------------------------------------------------------------

  describe "apply_has_expiry/2" do
    test "true matches keys with expires_at set, regardless of past/future" do
      cluster = insert_cluster()
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      past_key = insert_key(cluster.id, %{expires_at: past})
      future_key = insert_key(cluster.id, %{expires_at: future})
      _no_expiry = insert_key(cluster.id, %{expires_at: nil})

      query = EnrollmentKeyFilters.apply_has_expiry(EnrollmentKey, [%{op: :==, value: true}])

      assert ids(query) == Enum.sort([past_key.id, future_key.id])
    end

    test "false matches keys with no expiry set" do
      cluster = insert_cluster()
      future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      _has_expiry = insert_key(cluster.id, %{expires_at: future})
      no_expiry = insert_key(cluster.id, %{expires_at: nil})

      query = EnrollmentKeyFilters.apply_has_expiry(EnrollmentKey, [%{op: :==, value: false}])

      assert ids(query) == [no_expiry.id]
    end
  end

  # ---------------------------------------------------------------------------
  # apply_has_name/2 — name IS [NOT] NULL
  # ---------------------------------------------------------------------------

  describe "apply_has_name/2" do
    test "true matches keys with a name set" do
      cluster = insert_cluster()
      labeled = insert_key(cluster.id, %{name: "prod-rollout"})
      _unlabeled = insert_key(cluster.id, %{name: nil})

      query = EnrollmentKeyFilters.apply_has_name(EnrollmentKey, [%{op: :==, value: true}])

      assert ids(query) == [labeled.id]
    end

    test "false matches keys with no name (e.g. issued by public endpoint)" do
      cluster = insert_cluster()
      _labeled = insert_key(cluster.id, %{name: "prod-rollout"})
      unlabeled = insert_key(cluster.id, %{name: nil})

      query = EnrollmentKeyFilters.apply_has_name(EnrollmentKey, [%{op: :==, value: false}])

      assert ids(query) == [unlabeled.id]
    end
  end

  # ---------------------------------------------------------------------------
  # apply_maybe/3 — pure dispatching helper. Doesn't need DB but worth
  # testing inside this file since it's part of the same module.
  # ---------------------------------------------------------------------------

  describe "apply_maybe/3" do
    test "nil filters → returns query unchanged, fun is not called" do
      query = :placeholder
      fun = fn _q, _f -> raise "should not be called" end

      assert EnrollmentKeyFilters.apply_maybe(query, nil, fun) == query
    end

    test "empty filters → returns query unchanged, fun is not called" do
      query = :placeholder
      fun = fn _q, _f -> raise "should not be called" end

      assert EnrollmentKeyFilters.apply_maybe(query, [], fun) == query
    end

    test "non-empty filters → fun is invoked with (query, filters)" do
      query = :base
      filters = [%{op: :==, value: true}]
      fun = fn q, f -> {:applied, q, f} end

      assert EnrollmentKeyFilters.apply_maybe(query, filters, fun) ==
               {:applied, :base, [%{op: :==, value: true}]}
    end
  end
end
