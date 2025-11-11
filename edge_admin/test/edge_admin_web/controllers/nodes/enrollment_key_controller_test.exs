# edge_admin_web/test/edge_admin_web/controllers/nodes/enrollment_key_controller_test.exs
defmodule EdgeAdminWeb.Controllers.Nodes.EnrollmentKeyControllerTest do
  use EdgeAdminWeb.ConnCase

  import Mox
  import EdgeAdmin.NodesFixtures

  setup :verify_on_exit!

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "create enrollment key for cluster" do
    test "creates permanent enrollment key successfully (default)", %{conn: conn} do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)
      cluster = cluster_fixture()

      expect(NexmakerMock, :create_enrollment_key, fn _network_name, params ->
        assert params[:expiration] == 3600
        assert params[:uses_remaining] == 1
        # Verify unique tag is generated
        assert is_list(params[:tags])
        assert length(params[:tags]) == 1
        [tag] = params[:tags]
        assert String.starts_with?(tag, "permanent-")
        {:ok, %{"value" => "nmkey-permanent-abc123"}}
      end)

      conn =
        post(conn, ~p"/api/clusters/#{cluster.id}/enrollment_keys", %{
          enrollment_key: %{expiry: 3600}
        })

      response = json_response(conn, 201)
      assert response["data"]["key_value"] == "nmkey-permanent-abc123"
      assert response["data"]["key_type"] == "permanent"
      assert response["data"]["tracked"] == false

      # Verify NOT tracked in DB
      ephemeral_key =
        EdgeAdmin.Repo.get_by(EdgeAdmin.Nodes.EphemeralEnrollmentKey,
          key_value: "nmkey-permanent-abc123"
        )

      refute ephemeral_key
    end

    test "creates ephemeral enrollment key successfully", %{conn: conn} do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)
      cluster = cluster_fixture()

      expect(NexmakerMock, :create_enrollment_key, fn _network_name, params ->
        assert params[:expiration] == 3600
        assert params[:uses_remaining] == 1
        # Verify unique tag is generated
        assert is_list(params[:tags])
        assert length(params[:tags]) == 1
        [tag] = params[:tags]
        assert String.starts_with?(tag, "ephemeral-")
        {:ok, %{"value" => "nmkey-ephemeral-abc123"}}
      end)

      conn =
        post(conn, ~p"/api/clusters/#{cluster.id}/enrollment_keys", %{
          enrollment_key: %{key_type: "ephemeral", expiry: 3600}
        })

      response = json_response(conn, 201)
      assert response["data"]["key_value"] == "nmkey-ephemeral-abc123"
      assert response["data"]["key_type"] == "ephemeral"
      assert response["data"]["tracked"] == true

      # Verify tracked in DB
      ephemeral_key =
        EdgeAdmin.Repo.get_by(EdgeAdmin.Nodes.EphemeralEnrollmentKey,
          key_value: "nmkey-ephemeral-abc123"
        )

      assert ephemeral_key
      assert ephemeral_key.cluster_id == cluster.id
    end

    test "uses default expiry and key_type if not provided", %{conn: conn} do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)
      cluster = cluster_fixture()

      expect(NexmakerMock, :create_enrollment_key, fn _network_name, params ->
        assert params[:expiration] == 86400
        # Verify unique tag is generated (defaults to permanent)
        assert is_list(params[:tags])
        assert length(params[:tags]) == 1
        [tag] = params[:tags]
        assert String.starts_with?(tag, "permanent-")
        {:ok, %{"value" => "nmkey-default"}}
      end)

      conn = post(conn, ~p"/api/clusters/#{cluster.id}/enrollment_keys", %{})

      response = json_response(conn, 201)
      assert response["data"]["key_value"] == "nmkey-default"
      assert response["data"]["key_type"] == "permanent"
      assert response["data"]["tracked"] == false
    end

    test "returns 404 when cluster doesn't exist", %{conn: conn} do
      invalid_cluster_id = Ecto.UUID.generate()

      conn =
        post(conn, ~p"/api/clusters/#{invalid_cluster_id}/enrollment_keys", %{
          enrollment_key: %{expiry: 3600}
        })

      assert json_response(conn, 404)
    end
  end

  describe "create enrollment key for default cluster" do
    test "creates permanent key for default cluster successfully", %{conn: conn} do
      # Set default cluster name in config
      Application.put_env(:edge_admin, :default_cluster_name, "default")

      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)
      cluster = cluster_fixture(%{name: "default"})

      expect(NexmakerMock, :create_enrollment_key, fn _network_name, params ->
        # Verify unique tag is generated
        assert is_list(params[:tags])
        assert length(params[:tags]) == 1
        [tag] = params[:tags]
        assert String.starts_with?(tag, "permanent-")
        {:ok, %{"value" => "nmkey-default-cluster"}}
      end)

      conn =
        post(conn, ~p"/api/clusters/default/enrollment_keys", %{
          enrollment_key: %{expiry: 7200}
        })

      response = json_response(conn, 201)
      assert response["data"]["key_value"] == "nmkey-default-cluster"
      assert response["data"]["key_type"] == "permanent"
      assert response["data"]["tracked"] == false
    end

    test "creates ephemeral key for default cluster successfully", %{conn: conn} do
      # Set default cluster name in config
      Application.put_env(:edge_admin, :default_cluster_name, "default")

      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)
      cluster = cluster_fixture(%{name: "default"})

      expect(NexmakerMock, :create_enrollment_key, fn _network_name, params ->
        # Verify unique tag is generated
        assert is_list(params[:tags])
        assert length(params[:tags]) == 1
        [tag] = params[:tags]
        assert String.starts_with?(tag, "ephemeral-")
        {:ok, %{"value" => "nmkey-default-ephemeral"}}
      end)

      conn =
        post(conn, ~p"/api/clusters/default/enrollment_keys", %{
          enrollment_key: %{key_type: "ephemeral", expiry: 7200}
        })

      response = json_response(conn, 201)
      assert response["data"]["key_value"] == "nmkey-default-ephemeral"
      assert response["data"]["key_type"] == "ephemeral"
      assert response["data"]["tracked"] == true

      # Verify tracked in DB
      ephemeral_key =
        EdgeAdmin.Repo.get_by(EdgeAdmin.Nodes.EphemeralEnrollmentKey,
          key_value: "nmkey-default-ephemeral"
        )

      assert ephemeral_key
      assert ephemeral_key.cluster_id == cluster.id
    end

    test "returns 400 when default cluster is not configured", %{conn: conn} do
      # Clear default cluster config
      Application.put_env(:edge_admin, :default_cluster_name, nil)

      conn = post(conn, ~p"/api/clusters/default/enrollment_keys", %{})

      response = json_response(conn, 400)
      assert response["error"] == "Default cluster not configured"
    end

    test "returns 404 when default cluster doesn't exist in DB", %{conn: conn} do
      # Set default cluster name but don't create the cluster
      Application.put_env(:edge_admin, :default_cluster_name, "nonexistent")

      conn = post(conn, ~p"/api/clusters/default/enrollment_keys", %{})

      response = json_response(conn, 404)
      assert response["error"] == "Default cluster not found"
    end
  end
end
