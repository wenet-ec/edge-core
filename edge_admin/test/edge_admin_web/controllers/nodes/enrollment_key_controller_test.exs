# edge_admin_web/test/edge_admin_web/controllers/nodes/enrollment_key_controller_test.exs
defmodule EdgeAdminWeb.Controllers.Nodes.EnrollmentKeyControllerTest do
  use EdgeAdminWeb.ConnCase

  import EdgeAdmin.NodesFixtures
  import Mox

  alias EdgeAdmin.Nodes.EphemeralEnrollmentKey

  setup :verify_on_exit!

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "create enrollment key for cluster" do
    test "retrieves permanent enrollment key successfully (default)", %{conn: conn} do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)
      cluster = cluster_fixture()

      # Mock listing all enrollment keys - returns keys with "default": true field
      expect(NexmakerMock, :list_enrollment_keys, fn ->
        {:ok,
         [
           %{
             "token" => "eyJ0b2tlbi1kZWZhdWx0LWFiYzEyMyJ9",
             "networks" => ["cluster-#{cluster.name}"],
             "default" => true
           }
         ]}
      end)

      conn =
        post(conn, ~p"/api/clusters/#{cluster.id}/enrollment_keys", %{})

      response = json_response(conn, 201)
      assert response["data"]["token"] == "eyJ0b2tlbi1kZWZhdWx0LWFiYzEyMyJ9"
      assert response["data"]["key_type"] == "permanent"
      assert response["data"]["tracked"] == false

      # Verify NOT tracked in DB
      ephemeral_key =
        EdgeAdmin.Repo.get_by(EphemeralEnrollmentKey,
          token: "eyJ0b2tlbi1kZWZhdWx0LWFiYzEyMyJ9"
        )

      refute ephemeral_key
    end

    test "creates ephemeral enrollment key successfully", %{conn: conn} do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)
      cluster = cluster_fixture()

      expect(NexmakerMock, :create_enrollment_key, fn _network_name, params ->
        # Ephemeral keys have fixed 1 hour expiration and 1 use
        assert params[:expiration] == 3600
        assert params[:uses_remaining] == 1
        # Verify unique tag is generated
        assert is_list(params[:tags])
        assert length(params[:tags]) == 1
        [tag] = params[:tags]
        assert String.starts_with?(tag, "ephemeral-")
        {:ok, %{"token" => "eyJ0b2tlbi1lcGhlbWVyYWwtYWJjMTIzIn0="}}
      end)

      conn =
        post(conn, ~p"/api/clusters/#{cluster.id}/enrollment_keys", %{
          enrollment_key: %{key_type: "ephemeral"}
        })

      response = json_response(conn, 201)
      assert response["data"]["token"] == "eyJ0b2tlbi1lcGhlbWVyYWwtYWJjMTIzIn0="
      assert response["data"]["key_type"] == "ephemeral"
      assert response["data"]["tracked"] == true

      # Verify tracked in DB
      ephemeral_key =
        EdgeAdmin.Repo.get_by(EphemeralEnrollmentKey,
          token: "eyJ0b2tlbi1lcGhlbWVyYWwtYWJjMTIzIn0="
        )

      assert ephemeral_key
      assert ephemeral_key.cluster_id == cluster.id
    end

    test "uses permanent key_type by default", %{conn: conn} do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)
      cluster = cluster_fixture()

      # Mock listing all enrollment keys
      expect(NexmakerMock, :list_enrollment_keys, fn ->
        {:ok,
         [
           %{
             "token" => "eyJ0b2tlbi1kZWZhdWx0LWtleSJ9",
             "networks" => ["cluster-#{cluster.name}"],
             "default" => true
           }
         ]}
      end)

      conn = post(conn, ~p"/api/clusters/#{cluster.id}/enrollment_keys", %{})

      response = json_response(conn, 201)
      assert response["data"]["token"] == "eyJ0b2tlbi1kZWZhdWx0LWtleSJ9"
      assert response["data"]["key_type"] == "permanent"
      assert response["data"]["tracked"] == false
    end

    test "returns 404 when cluster doesn't exist", %{conn: conn} do
      invalid_cluster_id = Ecto.UUID.generate()

      conn =
        post(conn, ~p"/api/clusters/#{invalid_cluster_id}/enrollment_keys", %{
          enrollment_key: %{}
        })

      assert json_response(conn, 404)
    end

    test "returns error when default key not found", %{conn: conn} do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)
      cluster = cluster_fixture()

      # Mock listing enrollment keys with no default key for this network
      expect(NexmakerMock, :list_enrollment_keys, fn ->
        {:ok,
         [
           %{
             "token" => "eyJ0b2tlbi1vdGhlciJ9",
             "networks" => ["other-network"],
             "default" => true
           }
         ]}
      end)

      conn = post(conn, ~p"/api/clusters/#{cluster.id}/enrollment_keys", %{})

      assert json_response(conn, 422)
    end
  end

  describe "create enrollment key for default cluster" do
    test "retrieves permanent key for default cluster successfully", %{conn: conn} do
      # Set default cluster name in config
      Application.put_env(:edge_admin, :default_cluster_name, "default")

      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)
      cluster = cluster_fixture(%{name: "default"})

      # Mock listing all enrollment keys
      expect(NexmakerMock, :list_enrollment_keys, fn ->
        {:ok,
         [
           %{
             "token" => "eyJ0b2tlbi1kZWZhdWx0LWNsdXN0ZXIifQ==",
             "networks" => ["cluster-default"],
             "default" => true
           }
         ]}
      end)

      conn =
        post(conn, ~p"/api/clusters/default/enrollment_keys", %{})

      response = json_response(conn, 201)
      assert response["data"]["token"] == "eyJ0b2tlbi1kZWZhdWx0LWNsdXN0ZXIifQ=="
      assert response["data"]["key_type"] == "permanent"
      assert response["data"]["tracked"] == false
    end

    test "creates ephemeral key for default cluster successfully", %{conn: conn} do
      # Set default cluster name in config
      Application.put_env(:edge_admin, :default_cluster_name, "default")

      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)
      cluster = cluster_fixture(%{name: "default"})

      expect(NexmakerMock, :create_enrollment_key, fn _network_name, params ->
        # Ephemeral keys have fixed 1 hour expiration and 1 use
        assert params[:expiration] == 3600
        assert params[:uses_remaining] == 1
        # Verify unique tag is generated
        assert is_list(params[:tags])
        assert length(params[:tags]) == 1
        [tag] = params[:tags]
        assert String.starts_with?(tag, "ephemeral-")
        {:ok, %{"token" => "eyJ0b2tlbi1kZWZhdWx0LWVwaGVtZXJhbCJ9"}}
      end)

      conn =
        post(conn, ~p"/api/clusters/default/enrollment_keys", %{
          enrollment_key: %{key_type: "ephemeral"}
        })

      response = json_response(conn, 201)
      assert response["data"]["token"] == "eyJ0b2tlbi1kZWZhdWx0LWVwaGVtZXJhbCJ9"
      assert response["data"]["key_type"] == "ephemeral"
      assert response["data"]["tracked"] == true

      # Verify tracked in DB
      ephemeral_key =
        EdgeAdmin.Repo.get_by(EphemeralEnrollmentKey,
          token: "eyJ0b2tlbi1kZWZhdWx0LWVwaGVtZXJhbCJ9"
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
