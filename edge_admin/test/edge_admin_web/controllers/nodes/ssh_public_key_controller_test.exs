# edge_admin/test/edge_admin_web/controllers/nodes/ssh_public_key_controller_test.exs
defmodule EdgeAdminWeb.Controllers.Nodes.SshPublicKeyControllerTest do
  use EdgeAdminWeb.ConnCase

  import EdgeAdmin.NodesFixtures

  @create_attrs %{
    public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 test@example.com",
    key_name: "test-key"
  }
  @invalid_attrs %{public_key: nil, key_name: nil}

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists all ssh_public_keys with pagination", %{conn: conn} do
      conn = get(conn, ~p"/api/ssh_public_keys")

      assert %{
               "data" => [],
               "pagination" => %{
                 "page" => 1,
                 "page_size" => 20,
                 "total" => 0,
                 "total_pages" => 0
               }
             } = json_response(conn, 200)
    end

    test "filters by ssh_username_id", %{conn: conn} do
      ssh_username = ssh_username_fixture()
      ssh_public_key = ssh_public_key_fixture(%{ssh_username_id: ssh_username.id})
      # Different username
      _other_key = ssh_public_key_fixture()

      conn = get(conn, ~p"/api/ssh_public_keys?ssh_username_id=#{ssh_username.id}")

      response = json_response(conn, 200)
      assert length(response["data"]) == 1
      assert hd(response["data"])["id"] == ssh_public_key.id
    end
  end

  describe "create ssh_public_key" do
    test "renders ssh_public_key when data is valid", %{conn: conn} do
      ssh_username = ssh_username_fixture()

      conn =
        post(conn, ~p"/api/ssh_usernames/#{ssh_username.id}/ssh_public_keys", ssh_public_key: @create_attrs)

      assert %{"id" => id} = json_response(conn, 201)["data"]

      conn = get(conn, ~p"/api/ssh_public_keys/#{id}")

      assert %{
               "id" => ^id,
               "key_name" => "test-key",
               "public_key" =>
                 "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 test@example.com",
               "ssh_username_id" => ssh_username_id,
               "inserted_at" => _,
               "updated_at" => _
             } = json_response(conn, 200)["data"]

      assert ssh_username_id == ssh_username.id
    end

    test "renders errors when data is invalid", %{conn: conn} do
      ssh_username = ssh_username_fixture()

      conn =
        post(conn, ~p"/api/ssh_usernames/#{ssh_username.id}/ssh_public_keys", ssh_public_key: @invalid_attrs)

      assert json_response(conn, 422)["errors"] != %{}
    end

    test "returns 404 when ssh_username does not exist", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      conn =
        post(conn, ~p"/api/ssh_usernames/#{fake_id}/ssh_public_keys", ssh_public_key: @create_attrs)

      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "show ssh_public_key" do
    test "renders ssh_public_key", %{conn: conn} do
      ssh_public_key = ssh_public_key_fixture()

      conn = get(conn, ~p"/api/ssh_public_keys/#{ssh_public_key}")

      assert %{
               "id" => id,
               "key_name" => "some key_name",
               "public_key" => _,
               "ssh_username_id" => _,
               "inserted_at" => _,
               "updated_at" => _
             } = json_response(conn, 200)["data"]

      assert id == ssh_public_key.id
    end

    test "returns 404 when ssh_public_key does not exist", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      assert_error_sent(404, fn ->
        get(conn, ~p"/api/ssh_public_keys/#{fake_id}")
      end)
    end
  end

  describe "delete ssh_public_key" do
    test "deletes chosen ssh_public_key", %{conn: conn} do
      ssh_public_key = ssh_public_key_fixture()

      conn = delete(conn, ~p"/api/ssh_public_keys/#{ssh_public_key}")
      assert response(conn, 204)

      assert_error_sent(404, fn ->
        get(conn, ~p"/api/ssh_public_keys/#{ssh_public_key}")
      end)
    end

    test "returns 404 when ssh_public_key does not exist", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      assert_error_sent(404, fn ->
        delete(conn, ~p"/api/ssh_public_keys/#{fake_id}")
      end)
    end
  end
end
