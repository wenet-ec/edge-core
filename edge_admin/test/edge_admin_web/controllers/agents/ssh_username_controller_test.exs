# edge_admin/test/edge_admin_web/controllers/agents/ssh_username_controller_test.exs
defmodule EdgeAdminWeb.Controllers.Agents.SshUsernameControllerTest do
  use EdgeAdminWeb.ConnCase

  import EdgeAdmin.NodesFixtures

  alias EdgeAdmin.Nodes

  setup %{conn: conn} do
    # Create node with api_token for authentication
    node = node_fixture(%{api_token: "test-api-token-123"})

    # Authenticated connection (agent)
    auth_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token-123")

    {:ok, conn: conn, auth_conn: auth_conn, node: node}
  end

  describe "GET /api/agents/ssh_usernames" do
    test "lists all SSH usernames for authenticated node", %{auth_conn: conn, node: node} do
      # Create SSH usernames with keys
      {:ok, username1} =
        Nodes.create_ssh_username(%{
          username: "deploy",
          password: "secret123",
          node_id: node.id
        })

      {:ok, key1} =
        Nodes.create_ssh_public_key(%{
          key_name: "laptop",
          public_key:
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 test@example.com",
          ssh_username_id: username1.id
        })

      {:ok, username2} =
        Nodes.create_ssh_username(%{
          username: "admin",
          password: nil,
          node_id: node.id
        })

      {:ok, key2} =
        Nodes.create_ssh_public_key(%{
          key_name: "ci",
          public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 ci@example.com",
          ssh_username_id: username2.id
        })

      conn = get(conn, ~p"/api/agents/ssh_usernames")

      assert %{"ssh_usernames" => ssh_usernames} = json_response(conn, 200)
      assert length(ssh_usernames) == 2

      # Find the deploy user
      deploy_user = Enum.find(ssh_usernames, fn u -> u["username"] == "deploy" end)
      assert deploy_user["password"] == "secret123"
      assert length(deploy_user["public_keys"]) == 1
      assert hd(deploy_user["public_keys"])["key_name"] == "laptop"

      # Find the admin user
      admin_user = Enum.find(ssh_usernames, fn u -> u["username"] == "admin" end)
      assert is_nil(admin_user["password"])
      assert length(admin_user["public_keys"]) == 1
      assert hd(admin_user["public_keys"])["key_name"] == "ci"
    end

    test "returns empty list when node has no SSH usernames", %{auth_conn: conn} do
      conn = get(conn, ~p"/api/agents/ssh_usernames")

      assert %{"ssh_usernames" => []} = json_response(conn, 200)
    end

    test "returns 401 without authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/agents/ssh_usernames")

      assert json_response(conn, 401)
    end

    test "returns 401 with invalid token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer invalid-token")
        |> get(~p"/api/agents/ssh_usernames")

      assert json_response(conn, 401)
    end

    test "only returns SSH usernames for the authenticated node", %{auth_conn: conn, node: node} do
      # Create username for this node
      {:ok, _username1} =
        Nodes.create_ssh_username(%{
          username: "my-user",
          node_id: node.id
        })

      # Create another node with username
      other_node = node_fixture(%{api_token: "other-token"})

      {:ok, _username2} =
        Nodes.create_ssh_username(%{
          username: "other-user",
          node_id: other_node.id
        })

      conn = get(conn, ~p"/api/agents/ssh_usernames")

      assert %{"ssh_usernames" => ssh_usernames} = json_response(conn, 200)
      assert length(ssh_usernames) == 1
      assert hd(ssh_usernames)["username"] == "my-user"
    end
  end
end
