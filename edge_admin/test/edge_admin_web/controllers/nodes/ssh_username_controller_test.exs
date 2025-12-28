# edge_admin/test/edge_admin_web/controllers/nodes/ssh_username_controller_test.exs
defmodule EdgeAdminWeb.Controllers.Nodes.SshUsernameControllerTest do
  use EdgeAdminWeb.ConnCase

  import EdgeAdmin.NodesFixtures

  @create_attrs %{
    username: "admin"
  }
  @create_attrs_with_password %{
    username: "admin",
    password: "secret123"
  }
  @create_attrs_with_keys %{
    username: "deploy",
    password: "secret456",
    public_keys: [
      %{
        key_name: "laptop",
        public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 user@laptop"
      },
      %{
        key_name: "ci",
        public_key: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7Z8nFkX+7rT9uJ2p9lH8... ci@server"
      }
    ]
  }
  @invalid_attrs %{
    username: nil
  }

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists all ssh_usernames with pagination", %{conn: conn} do
      conn = get(conn, ~p"/api/ssh_usernames")
      response = json_response(conn, 200)

      assert %{
               "data" => [],
               "pagination" => %{
                 "page" => 1,
                 "page_size" => 20,
                 "total" => 0,
                 "total_pages" => 0
               }
             } = response
    end

    test "lists ssh_usernames with filtering by node_id", %{conn: conn} do
      node1 = node_fixture()
      node2 = node_fixture()
      ssh_username1 = ssh_username_fixture(%{node_id: node1.id, username: "user1"})
      _ssh_username2 = ssh_username_fixture(%{node_id: node2.id, username: "user2"})

      conn = get(conn, ~p"/api/ssh_usernames?node_id=#{node1.id}")
      response = json_response(conn, 200)

      assert %{"data" => [data]} = response
      assert data["id"] == ssh_username1.id
      assert data["username"] == "user1"
      assert data["node_id"] == node1.id
    end

    test "supports pagination parameters", %{conn: conn} do
      _ssh_username = ssh_username_fixture()

      conn = get(conn, ~p"/api/ssh_usernames?page=1&page_size=5")
      response = json_response(conn, 200)

      assert %{
               "pagination" => %{
                 "page" => 1,
                 "page_size" => 5
               }
             } = response
    end
  end

  describe "create ssh_username" do
    test "renders ssh_username when data is valid", %{conn: conn} do
      node = node_fixture()

      conn = post(conn, ~p"/api/nodes/#{node.id}/ssh_usernames", ssh_username: @create_attrs)
      assert %{"id" => id} = json_response(conn, 201)["data"]

      conn = get(conn, ~p"/api/ssh_usernames/#{id}")

      assert %{
               "id" => ^id,
               "username" => "admin",
               "node_id" => node_id
             } = json_response(conn, 200)["data"]

      assert node_id == node.id
    end

    test "renders ssh_username with password when provided", %{conn: conn} do
      node = node_fixture()

      conn = post(conn, ~p"/api/nodes/#{node.id}/ssh_usernames", ssh_username: @create_attrs_with_password)
      assert %{"id" => id, "password" => password} = json_response(conn, 201)["data"]
      assert password == "secret123"

      conn = get(conn, ~p"/api/ssh_usernames/#{id}")

      assert %{
               "id" => ^id,
               "username" => "admin",
               "password" => "secret123",
               "node_id" => node_id
             } = json_response(conn, 200)["data"]

      assert node_id == node.id
    end

    test "creates ssh_username with password and public keys in single transaction", %{conn: conn} do
      node = node_fixture()

      conn = post(conn, ~p"/api/nodes/#{node.id}/ssh_usernames", ssh_username: @create_attrs_with_keys)
      response = json_response(conn, 201)["data"]

      assert %{
               "id" => id,
               "username" => "deploy",
               "password" => "secret456",
               "public_keys" => public_keys
             } = response

      assert length(public_keys) == 2
      assert Enum.any?(public_keys, fn key -> key["key_name"] == "laptop" end)
      assert Enum.any?(public_keys, fn key -> key["key_name"] == "ci" end)

      # Verify the username with keys can be retrieved
      conn = get(conn, ~p"/api/ssh_usernames/#{id}")
      response = json_response(conn, 200)["data"]

      assert %{"username" => "deploy", "public_keys" => keys} = response
      assert length(keys) == 2
    end

    test "renders errors when data is invalid", %{conn: conn} do
      node = node_fixture()

      conn = post(conn, ~p"/api/nodes/#{node.id}/ssh_usernames", ssh_username: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "renders error when node does not exist", %{conn: conn} do
      fake_node_id = Ecto.UUID.generate()

      conn = post(conn, ~p"/api/nodes/#{fake_node_id}/ssh_usernames", ssh_username: @create_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "enforces unique username per node", %{conn: conn} do
      node = node_fixture()
      _existing = ssh_username_fixture(%{node_id: node.id, username: "admin"})

      conn = post(conn, ~p"/api/nodes/#{node.id}/ssh_usernames", ssh_username: @create_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "rolls back transaction if any public key is invalid", %{conn: conn} do
      node = node_fixture()

      invalid_keys_attrs = %{
        username: "testuser",
        public_keys: [
          %{
            key_name: "valid",
            public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 user@laptop"
          },
          %{
            key_name: "invalid",
            public_key: "not-a-valid-ssh-key"
          }
        ]
      }

      conn = post(conn, ~p"/api/nodes/#{node.id}/ssh_usernames", ssh_username: invalid_keys_attrs)
      assert json_response(conn, 422)["errors"] != %{}

      # Verify no username was created (transaction rolled back)
      conn = get(conn, ~p"/api/ssh_usernames?username=testuser")
      response = json_response(conn, 200)
      assert response["data"] == []
    end
  end

  describe "show ssh_username" do
    test "renders ssh_username when it exists", %{conn: conn} do
      ssh_username = ssh_username_fixture()

      conn = get(conn, ~p"/api/ssh_usernames/#{ssh_username.id}")

      assert %{
               "id" => id,
               "username" => username,
               "node_id" => node_id
             } = json_response(conn, 200)["data"]

      assert id == ssh_username.id
      assert username == ssh_username.username
      assert node_id == ssh_username.node_id
    end

    test "renders ssh_username with public_keys when present", %{conn: conn} do
      node = node_fixture()
      ssh_username = ssh_username_fixture(%{node_id: node.id, username: "testuser"})

      # Create public keys
      key1 =
        ssh_public_key_fixture(%{
          ssh_username_id: ssh_username.id,
          key_name: "laptop",
          public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 user@laptop"
        })

      key2 =
        ssh_public_key_fixture(%{
          ssh_username_id: ssh_username.id,
          key_name: "server",
          public_key: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7Z8nFkX+7rT9uJ2p9lH8... ci@server"
        })

      conn = get(conn, ~p"/api/ssh_usernames/#{ssh_username.id}")
      response = json_response(conn, 200)["data"]

      assert %{
               "id" => _id,
               "username" => "testuser",
               "public_keys" => public_keys
             } = response

      assert length(public_keys) == 2
      assert Enum.any?(public_keys, fn key -> key["key_name"] == "laptop" end)
      assert Enum.any?(public_keys, fn key -> key["key_name"] == "server" end)
    end

    test "renders 404 when ssh_username does not exist", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      assert_error_sent(404, fn ->
        get(conn, ~p"/api/ssh_usernames/#{fake_id}")
      end)
    end
  end

  describe "delete ssh_username" do
    setup [:create_ssh_username]

    test "deletes chosen ssh_username", %{conn: conn, ssh_username: ssh_username} do
      conn = delete(conn, ~p"/api/ssh_usernames/#{ssh_username.id}")
      assert response(conn, 204)

      assert_error_sent(404, fn ->
        get(conn, ~p"/api/ssh_usernames/#{ssh_username.id}")
      end)
    end

    test "cascades deletion to associated public keys", %{conn: conn, ssh_username: ssh_username} do
      # Create a public key for this username
      public_key = ssh_public_key_fixture(%{ssh_username_id: ssh_username.id})

      conn = delete(conn, ~p"/api/ssh_usernames/#{ssh_username.id}")
      assert response(conn, 204)

      # Verify the public key was also deleted by trying to fetch it
      assert_raise Ecto.NoResultsError, fn ->
        EdgeAdmin.Nodes.get_ssh_public_key!(public_key.id)
      end
    end

    test "renders 404 when ssh_username does not exist", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      assert_error_sent(404, fn ->
        delete(conn, ~p"/api/ssh_usernames/#{fake_id}")
      end)
    end
  end

  defp create_ssh_username(_) do
    ssh_username = ssh_username_fixture()
    %{ssh_username: ssh_username}
  end
end
