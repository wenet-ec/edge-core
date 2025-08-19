# edge_admin/test/edge_admin_web/controllers/commands/command_controller_test.exs
defmodule EdgeAdminWeb.Commands.CommandControllerTest do
  use EdgeAdminWeb.ConnCase

  import EdgeAdmin.CommandsFixtures
  import EdgeAdmin.NodesFixtures

  @create_attrs %{
    command_text: "echo hello\nls -la"
  }

  @create_target_nodes_attrs %{
    command_text: "systemctl restart nginx",
    # Will be filled in tests
    target_nodes: [],
    target_all: false
  }

  @create_target_all_attrs %{
    command_text: "apt update && apt upgrade -y",
    target_all: true
  }

  @invalid_attrs %{command_text: nil}

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists commands with pagination metadata", %{conn: conn} do
      conn = get(conn, ~p"/api/commands")
      response = json_response(conn, 200)

      assert response["data"] == []
      assert response["pagination"]["total"] == 0
    end

    test "supports filtering", %{conn: conn} do
      command_fixture(%{command_text: "nginx restart service"})
      command_fixture(%{command_text: "apache start daemon"})
      command_fixture(%{command_text: "systemctl status nginx"})

      # Test filtering with wildcards
      conn = get(conn, ~p"/api/commands?command_text=*nginx*")
      response = json_response(conn, 200)

      assert length(response["data"]) == 2
      assert response["filters"] == %{"command_text" => "*nginx*"}

      nginx_commands = Enum.map(response["data"], & &1["command_text"])
      assert "nginx restart service" in nginx_commands
      assert "systemctl status nginx" in nginx_commands

      # Test filtering with different pattern
      conn = get(conn, ~p"/api/commands?command_text=*apache*")
      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert hd(response["data"])["command_text"] == "apache start daemon"
      assert response["filters"] == %{"command_text" => "*apache*"}

      # Test no matches
      conn = get(conn, ~p"/api/commands?command_text=*mysql*")
      response = json_response(conn, 200)

      assert length(response["data"]) == 0
      assert response["filters"] == %{"command_text" => "*mysql*"}
    end

    test "supports pagination", %{conn: conn} do
      # Create multiple commands
      for i <- 1..5 do
        command_fixture(%{command_text: "command #{i}"})
      end

      conn = get(conn, ~p"/api/commands?page_size=2")
      response = json_response(conn, 200)

      assert length(response["data"]) == 2
      assert response["pagination"]["page"] == 1
      assert response["pagination"]["page_size"] == 2
      assert response["pagination"]["total"] == 5
      assert response["pagination"]["has_next"] == true
    end
  end

  describe "create command" do
    test "creates command with basic attributes", %{conn: conn} do
      conn = post(conn, ~p"/api/commands", command: @create_attrs)
      assert %{"id" => id} = json_response(conn, 201)["data"]

      conn = get(conn, ~p"/api/commands/#{id}")

      assert %{
               "id" => ^id,
               "command_text" => "echo hello\nls -la"
             } = json_response(conn, 200)["data"]
    end

    test "creates command with target_nodes", %{conn: conn} do
      node1 = node_fixture()
      node2 = node_fixture()

      attrs = %{@create_target_nodes_attrs | target_nodes: [node1.id, node2.id]}

      conn = post(conn, ~p"/api/commands", command: attrs)
      assert %{"id" => _id} = json_response(conn, 201)["data"]

      # The command should be created and dispatch workers should be enqueued
      # We don't test the actual worker execution here, just the controller response
    end

    test "creates command with target_all", %{conn: conn} do
      conn = post(conn, ~p"/api/commands", command: @create_target_all_attrs)
      assert %{"id" => _id} = json_response(conn, 201)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/api/commands", command: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "validates command_text format", %{conn: conn} do
      invalid_attrs = %{command_text: "   \n\t  "}
      conn = post(conn, ~p"/api/commands", command: invalid_attrs)
      assert json_response(conn, 422)["errors"]["command_text"]
    end
  end

  describe "show command" do
    test "returns command by ID", %{conn: conn} do
      command = command_fixture()
      conn = get(conn, ~p"/api/commands/#{command}")

      response = json_response(conn, 200)["data"]
      assert response["id"] == command.id
      assert response["command_text"] == command.command_text
    end

    test "returns 404 for non-existent command", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      assert_error_sent(404, fn ->
        get(conn, ~p"/api/commands/#{fake_id}")
      end)
    end
  end
end
