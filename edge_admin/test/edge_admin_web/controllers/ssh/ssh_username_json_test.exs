# edge_admin/test/edge_admin_web/controllers/ssh/ssh_username_json_test.exs
defmodule EdgeAdminWeb.Controllers.Ssh.SshUsernameJSONTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  alias EdgeAdmin.Ssh.Schemas.SshPublicKey
  alias EdgeAdmin.Ssh.Schemas.SshUsername
  alias EdgeAdminWeb.Controllers.Ssh.SshUsernameJSON

  @now ~U[2026-01-01 10:00:00Z]

  defp fake_conn do
    Plug.Conn.assign(build_conn(), :request_id, "test-request-id")
  end

  defp fake_public_key(overrides \\ %{}) do
    Map.merge(
      %SshPublicKey{
        id: "key-uuid-1",
        key_name: "my-laptop",
        public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA test@example.com",
        ssh_username_id: "user-uuid-1",
        inserted_at: @now,
        updated_at: @now
      },
      overrides
    )
  end

  defp fake_username(overrides \\ %{}) do
    Map.merge(
      %SshUsername{
        id: "user-uuid-1",
        username: "deploy",
        password_hash: nil,
        node_id: "node-uuid-1",
        ssh_public_keys: [],
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

  # -----------------------------------------------------------------------
  # show/1
  # -----------------------------------------------------------------------

  describe "show/1" do
    test "wraps username in %{data: ...}" do
      result = SshUsernameJSON.show(%{conn: fake_conn(), ssh_username: fake_username()})
      assert Map.has_key?(result, :data)
    end

    test "data contains all required fields" do
      data = SshUsernameJSON.show(%{conn: fake_conn(), ssh_username: fake_username()}).data

      for key <- [:id, :username, :has_password, :node_id, :public_keys, :inserted_at, :updated_at] do
        assert Map.has_key?(data, key), "expected key #{inspect(key)} to be present"
      end
    end

    test "scalar fields are passed through correctly" do
      username = fake_username(%{username: "admin", node_id: "node-uuid-2"})
      data = SshUsernameJSON.show(%{conn: fake_conn(), ssh_username: username}).data
      assert data.id == "user-uuid-1"
      assert data.username == "admin"
      assert data.node_id == "node-uuid-2"
      assert data.inserted_at == @now
      assert data.updated_at == @now
    end
  end

  # -----------------------------------------------------------------------
  # show/1 — has_password delegation
  # -----------------------------------------------------------------------

  describe "show/1 — has_password" do
    test "has_password is false when password_hash is nil" do
      username = fake_username(%{password_hash: nil})
      data = SshUsernameJSON.show(%{conn: fake_conn(), ssh_username: username}).data
      assert data.has_password == false
    end

    test "has_password is true when password_hash is set" do
      username = fake_username(%{password_hash: "$argon2id$v=19$m=65536,t=3,p=4$abc123"})
      data = SshUsernameJSON.show(%{conn: fake_conn(), ssh_username: username}).data
      assert data.has_password == true
    end

    test "has_password result is a boolean, not the hash itself" do
      username = fake_username(%{password_hash: "some-hash"})
      data = SshUsernameJSON.show(%{conn: fake_conn(), ssh_username: username}).data
      assert is_boolean(data.has_password)
    end

    test "raw password_hash field is NOT exposed in output" do
      username = fake_username(%{password_hash: "super-secret-hash"})
      data = SshUsernameJSON.show(%{conn: fake_conn(), ssh_username: username}).data
      refute Map.has_key?(data, :password_hash)
    end
  end

  # -----------------------------------------------------------------------
  # show/1 — nested public_keys rendering
  # -----------------------------------------------------------------------

  describe "show/1 — public_keys" do
    test "public_keys is empty list when username has no keys" do
      data = SshUsernameJSON.show(%{conn: fake_conn(), ssh_username: fake_username(%{ssh_public_keys: []})}).data
      assert data.public_keys == []
    end

    test "each public key has id, key_name, public_key, inserted_at, updated_at" do
      key = fake_public_key()
      username = fake_username(%{ssh_public_keys: [key]})
      data = SshUsernameJSON.show(%{conn: fake_conn(), ssh_username: username}).data
      key_data = hd(data.public_keys)
      assert Map.has_key?(key_data, :id)
      assert Map.has_key?(key_data, :key_name)
      assert Map.has_key?(key_data, :public_key)
      assert Map.has_key?(key_data, :inserted_at)
      assert Map.has_key?(key_data, :updated_at)
    end

    test "nested key does NOT expose ssh_username_id (unlike SshPublicKeyJSON)" do
      key = fake_public_key(%{ssh_username_id: "user-uuid-1"})
      username = fake_username(%{ssh_public_keys: [key]})
      data = SshUsernameJSON.show(%{conn: fake_conn(), ssh_username: username}).data
      key_data = hd(data.public_keys)
      refute Map.has_key?(key_data, :ssh_username_id)
    end

    test "nested key has exactly the expected fields — no extras" do
      key = fake_public_key()
      username = fake_username(%{ssh_public_keys: [key]})
      data = SshUsernameJSON.show(%{conn: fake_conn(), ssh_username: username}).data
      key_data = hd(data.public_keys)

      assert MapSet.equal?(
               MapSet.new(Map.keys(key_data)),
               MapSet.new([:id, :key_name, :public_key, :inserted_at, :updated_at])
             )
    end

    test "key scalar fields are passed through correctly" do
      key =
        fake_public_key(%{
          id: "key-uuid-2",
          key_name: "work-laptop",
          public_key: "ssh-rsa AAAAB3Nza work@example.com"
        })

      username = fake_username(%{ssh_public_keys: [key]})
      data = SshUsernameJSON.show(%{conn: fake_conn(), ssh_username: username}).data
      key_data = hd(data.public_keys)
      assert key_data.id == "key-uuid-2"
      assert key_data.key_name == "work-laptop"
      assert key_data.public_key == "ssh-rsa AAAAB3Nza work@example.com"
      assert key_data.inserted_at == @now
      assert key_data.updated_at == @now
    end

    test "multiple keys rendered in order" do
      key1 = fake_public_key(%{id: "key-1", key_name: "laptop"})
      key2 = fake_public_key(%{id: "key-2", key_name: "desktop"})
      username = fake_username(%{ssh_public_keys: [key1, key2]})
      data = SshUsernameJSON.show(%{conn: fake_conn(), ssh_username: username}).data
      assert length(data.public_keys) == 2
      assert Enum.map(data.public_keys, & &1.id) == ["key-1", "key-2"]
    end
  end

  # -----------------------------------------------------------------------
  # index/1 — data array
  # -----------------------------------------------------------------------

  describe "index/1 — data array" do
    test "result has :data and :meta keys" do
      result = SshUsernameJSON.index(%{conn: fake_conn(), ssh_usernames: [], meta: fake_meta()})
      assert Map.has_key?(result, :data)
      assert Map.has_key?(result, :meta)
    end

    test "empty ssh_usernames produces empty data list" do
      result = SshUsernameJSON.index(%{conn: fake_conn(), ssh_usernames: [], meta: fake_meta()})
      assert result.data == []
    end

    test "each username is rendered with has_password delegation" do
      username = fake_username(%{password_hash: "hash"})
      result = SshUsernameJSON.index(%{conn: fake_conn(), ssh_usernames: [username], meta: fake_meta()})
      assert length(result.data) == 1
      assert hd(result.data).has_password == true
    end

    test "multiple usernames rendered in order" do
      u1 = fake_username(%{id: "user-1", username: "deploy"})
      u2 = fake_username(%{id: "user-2", username: "admin"})
      result = SshUsernameJSON.index(%{conn: fake_conn(), ssh_usernames: [u1, u2], meta: fake_meta()})
      assert length(result.data) == 2
      assert Enum.map(result.data, & &1.id) == ["user-1", "user-2"]
    end
  end

  # -----------------------------------------------------------------------
  # index/1 — pagination field renames
  # -----------------------------------------------------------------------

  describe "index/1 — pagination field renames from Flop.Meta" do
    test "current_page is renamed to page" do
      result = SshUsernameJSON.index(%{conn: fake_conn(), ssh_usernames: [], meta: fake_meta(current_page: 2)})
      assert Map.has_key?(result.meta.pagination, :page)
      refute Map.has_key?(result.meta.pagination, :current_page)
      assert result.meta.pagination.page == 2
    end

    test "total_count passed through as total_count" do
      result = SshUsernameJSON.index(%{conn: fake_conn(), ssh_usernames: [], meta: fake_meta(total_count: 42)})
      assert Map.has_key?(result.meta.pagination, :total_count)
      refute Map.has_key?(result.meta.pagination, :total)
      assert result.meta.pagination.total_count == 42
    end

    test "has_next_page? is renamed to has_next" do
      result = SshUsernameJSON.index(%{conn: fake_conn(), ssh_usernames: [], meta: fake_meta(has_next_page?: true)})
      assert Map.has_key?(result.meta.pagination, :has_next)
      refute Map.has_key?(result.meta.pagination, :has_next_page?)
      assert result.meta.pagination.has_next == true
    end

    test "has_previous_page? is renamed to has_prev" do
      result = SshUsernameJSON.index(%{conn: fake_conn(), ssh_usernames: [], meta: fake_meta(has_previous_page?: true)})
      assert Map.has_key?(result.meta.pagination, :has_prev)
      refute Map.has_key?(result.meta.pagination, :has_previous_page?)
      assert result.meta.pagination.has_prev == true
    end

    test "page_size is passed through unchanged" do
      result = SshUsernameJSON.index(%{conn: fake_conn(), ssh_usernames: [], meta: fake_meta(page_size: 50)})
      assert result.meta.pagination.page_size == 50
    end

    test "total_pages is passed through unchanged" do
      result = SshUsernameJSON.index(%{conn: fake_conn(), ssh_usernames: [], meta: fake_meta(total_pages: 3)})
      assert result.meta.pagination.total_pages == 3
    end

    test "has_next false is preserved" do
      result = SshUsernameJSON.index(%{conn: fake_conn(), ssh_usernames: [], meta: fake_meta(has_next_page?: false)})
      assert result.meta.pagination.has_next == false
    end

    test "has_prev false is preserved" do
      result =
        SshUsernameJSON.index(%{conn: fake_conn(), ssh_usernames: [], meta: fake_meta(has_previous_page?: false)})

      assert result.meta.pagination.has_prev == false
    end

    test "pagination has exactly the expected keys" do
      result = SshUsernameJSON.index(%{conn: fake_conn(), ssh_usernames: [], meta: fake_meta()})

      assert MapSet.equal?(
               MapSet.new(Map.keys(result.meta.pagination)),
               MapSet.new([:page, :page_size, :total_count, :total_pages, :has_next, :has_prev, :next_page, :prev_page])
             )
    end
  end
end
