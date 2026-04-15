# edge_admin/test/edge_admin_web/controllers/nodes/enrollment_key_json_test.exs
defmodule EdgeAdminWeb.Controllers.Nodes.EnrollmentKeyJSONTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.EnrollmentKey
  alias EdgeAdminWeb.Controllers.Nodes.EnrollmentKeyJSON

  @now ~U[2026-01-01 10:00:00Z]

  defp fake_conn do
    Plug.Conn.assign(build_conn(), :request_id, "test-request-id")
  end

  defp fake_cluster(overrides \\ %{}) do
    Map.merge(%Cluster{id: "cluster-uuid-1", name: "prod"}, overrides)
  end

  defp fake_key(overrides \\ %{}) do
    Map.merge(
      %EnrollmentKey{
        id: "key-uuid-1",
        cluster: fake_cluster(),
        key: "eyJhZG1pbl91cmxzIjpbXSwibm9uY2UiOiJhYmMifQ==",
        uses_remaining: 5,
        expired_at: nil,
        last_used_at: nil,
        inserted_at: @now,
        updated_at: @now
      },
      overrides
    )
  end

  defp fake_meta(overrides \\ []) do
    struct(
      Flop.Meta,
      Keyword.merge(
        [
          current_page: 1,
          page_size: 20,
          total_count: 1,
          total_pages: 1,
          has_next_page?: false,
          has_previous_page?: false
        ],
        overrides
      )
    )
  end

  # ---------------------------------------------------------------------------
  # show/1
  # ---------------------------------------------------------------------------

  describe "show/1" do
    test "wraps data under :data key" do
      result = EnrollmentKeyJSON.show(%{conn: fake_conn(), enrollment_key: fake_key()})
      assert Map.has_key?(result, :data)
    end

    test "all 8 expected fields are present" do
      data = EnrollmentKeyJSON.show(%{conn: fake_conn(), enrollment_key: fake_key()}).data
      expected_keys = ~w(id cluster_name key uses_remaining expired_at last_used_at inserted_at updated_at)a
      for key <- expected_keys, do: assert(Map.has_key?(data, key), "missing key: #{key}")
    end

    test "id is passed through" do
      data = EnrollmentKeyJSON.show(%{conn: fake_conn(), enrollment_key: fake_key(%{id: "test-id"})}).data
      assert data.id == "test-id"
    end

    test "cluster_name comes from preloaded cluster association" do
      key = fake_key(%{cluster: fake_cluster(%{name: "staging"})})
      data = EnrollmentKeyJSON.show(%{conn: fake_conn(), enrollment_key: key}).data
      assert data.cluster_name == "staging"
    end

    test "key blob is passed through" do
      blob = "eyJhZG1pbl91cmxzIjpbXX0="
      data = EnrollmentKeyJSON.show(%{conn: fake_conn(), enrollment_key: fake_key(%{key: blob})}).data
      assert data.key == blob
    end

    test "uses_remaining nil (unlimited) is passed through" do
      data = EnrollmentKeyJSON.show(%{conn: fake_conn(), enrollment_key: fake_key(%{uses_remaining: nil})}).data
      assert data.uses_remaining == nil
    end

    test "expired_at is nil when unset" do
      data = EnrollmentKeyJSON.show(%{conn: fake_conn(), enrollment_key: fake_key(%{expired_at: nil})}).data
      assert data.expired_at == nil
    end

    test "expired_at is passed through when set" do
      dt = ~U[2027-01-01 00:00:00Z]
      data = EnrollmentKeyJSON.show(%{conn: fake_conn(), enrollment_key: fake_key(%{expired_at: dt})}).data
      assert data.expired_at == dt
    end

    test "last_used_at is nil when unset" do
      data = EnrollmentKeyJSON.show(%{conn: fake_conn(), enrollment_key: fake_key(%{last_used_at: nil})}).data
      assert data.last_used_at == nil
    end

    test "last_used_at is passed through when set" do
      data = EnrollmentKeyJSON.show(%{conn: fake_conn(), enrollment_key: fake_key(%{last_used_at: @now})}).data
      assert data.last_used_at == @now
    end

    test "inserted_at and updated_at are passed through" do
      data = EnrollmentKeyJSON.show(%{conn: fake_conn(), enrollment_key: fake_key()}).data
      assert data.inserted_at == @now
      assert data.updated_at == @now
    end
  end

  # ---------------------------------------------------------------------------
  # index/1 — data array
  # ---------------------------------------------------------------------------

  describe "index/1 — data array" do
    test "empty key list returns empty data array" do
      result = EnrollmentKeyJSON.index(%{conn: fake_conn(), enrollment_keys: [], meta: fake_meta(total_count: 0)})
      assert result.data == []
    end

    test "single key returns data array with one element" do
      result = EnrollmentKeyJSON.index(%{conn: fake_conn(), enrollment_keys: [fake_key()], meta: fake_meta()})
      assert length(result.data) == 1
    end

    test "multiple keys returned in order" do
      k1 = fake_key(%{id: "id-1"})
      k2 = fake_key(%{id: "id-2"})

      result =
        EnrollmentKeyJSON.index(%{conn: fake_conn(), enrollment_keys: [k1, k2], meta: fake_meta(total_count: 2)})

      assert [d1, d2] = result.data
      assert d1.id == "id-1"
      assert d2.id == "id-2"
    end

    test "each element contains the key blob field" do
      result = EnrollmentKeyJSON.index(%{conn: fake_conn(), enrollment_keys: [fake_key()], meta: fake_meta()})
      [data] = result.data
      assert Map.has_key?(data, :key)
    end
  end

  # ---------------------------------------------------------------------------
  # index/1 — pagination rename
  # ---------------------------------------------------------------------------

  describe "index/1 — pagination shape" do
    setup do
      meta =
        fake_meta(
          current_page: 2,
          page_size: 10,
          total_count: 55,
          total_pages: 6,
          has_next_page?: true,
          has_previous_page?: true
        )

      result = EnrollmentKeyJSON.index(%{conn: fake_conn(), enrollment_keys: [], meta: meta})
      %{pagination: result.meta.pagination}
    end

    test "page = meta.current_page", %{pagination: p} do
      assert p.page == 2
    end

    test "page_size = meta.page_size", %{pagination: p} do
      assert p.page_size == 10
    end

    test "total_count = meta.total_count", %{pagination: p} do
      assert p.total_count == 55
    end

    test "total_pages = meta.total_pages", %{pagination: p} do
      assert p.total_pages == 6
    end

    test "has_next = meta.has_next_page?", %{pagination: p} do
      assert p.has_next == true
    end

    test "has_prev = meta.has_previous_page?", %{pagination: p} do
      assert p.has_prev == true
    end
  end
end
