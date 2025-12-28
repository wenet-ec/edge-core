# edge_admin_web/test/edge_admin_web/controllers/nodes/cluster_controller_test.exs
defmodule EdgeAdminWeb.Controllers.Nodes.ClusterControllerTest do
  use EdgeAdminWeb.ConnCase

  import EdgeAdmin.NodesFixtures
  import Mox

  setup :verify_on_exit!

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists all clusters with pagination", %{conn: conn} do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)
      cluster = cluster_fixture()

      conn = get(conn, ~p"/api/clusters")
      response = json_response(conn, 200)

      assert length(response["data"]) >= 1
      assert response["pagination"]["page"] == 1
      assert response["pagination"]["total"] >= 1

      cluster_data = Enum.find(response["data"], fn c -> c["id"] == cluster.id end)
      assert cluster_data["ipv4_range"] == cluster.ipv4_range
      assert cluster_data["node_count"] == 0
      assert cluster_data["network_name"]
      assert cluster_data["dns_domain"]
    end

    test "filters clusters by ipv4_range", %{conn: conn} do
      expect(NexmakerMock, :create_network, 2, fn _, _ -> {:ok, %{}} end)

      cluster1 = cluster_fixture(%{ipv4_range: "100.64.1.0/24"})
      _cluster2 = cluster_fixture(%{ipv4_range: "100.64.2.0/24"})

      conn = get(conn, ~p"/api/clusters?ipv4_range=100.64.1")
      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert hd(response["data"])["id"] == cluster1.id
      assert hd(response["data"])["ipv4_range"] =~ "100.64.1"
      assert response["pagination"]["total"] == 1
    end

    test "supports pagination parameters", %{conn: conn} do
      expect(NexmakerMock, :create_network, 3, fn _, _ -> {:ok, %{}} end)

      _cluster1 = cluster_fixture(%{ipv4_range: "100.64.10.0/24"})
      _cluster2 = cluster_fixture(%{ipv4_range: "100.64.20.0/24"})
      _cluster3 = cluster_fixture(%{ipv4_range: "100.64.30.0/24"})

      # Page 1 with page_size=2
      conn = get(conn, ~p"/api/clusters?page=1&page_size=2")
      response = json_response(conn, 200)

      assert length(response["data"]) == 2
      assert response["pagination"]["page"] == 1
      assert response["pagination"]["page_size"] == 2
      assert response["pagination"]["has_next"] == true
    end

    test "supports sorting", %{conn: conn} do
      expect(NexmakerMock, :create_network, 2, fn _, _ -> {:ok, %{}} end)

      cluster1 = cluster_fixture(%{ipv4_range: "100.64.1.0/24"})
      cluster2 = cluster_fixture(%{ipv4_range: "100.64.2.0/24"})

      # Sort by ipv4_range ascending
      conn = get(conn, ~p"/api/clusters?sort=ipv4_range:asc")
      response = json_response(conn, 200)

      assert hd(response["data"])["id"] == cluster1.id
      assert response["sort"] == ["ipv4_range:asc"]
    end

    test "filters by node_count with range queries", %{conn: conn} do
      expect(NexmakerMock, :create_network, 3, fn _, _ -> {:ok, %{}} end)

      cluster1 = cluster_fixture(%{ipv4_range: "100.64.1.0/24"})
      cluster2 = cluster_fixture(%{ipv4_range: "100.64.2.0/24"})
      cluster3 = cluster_fixture(%{ipv4_range: "100.64.3.0/24"})

      # Add nodes to clusters
      node_fixture(%{cluster_id: cluster1.id})
      node_fixture(%{cluster_id: cluster2.id})
      node_fixture(%{cluster_id: cluster2.id})

      # Filter: clusters with exactly 0 nodes
      conn = get(conn, ~p"/api/clusters?node_count=0")
      response = json_response(conn, 200)
      assert length(response["data"]) == 1
      assert hd(response["data"])["id"] == cluster3.id

      # Filter: clusters with >= 1 node
      conn = get(conn, ~p"/api/clusters?node_count=gte:1")
      response = json_response(conn, 200)
      assert length(response["data"]) == 2

      # Filter: clusters with >= 2 nodes
      conn = get(conn, ~p"/api/clusters?node_count=gte:2")
      response = json_response(conn, 200)
      assert length(response["data"]) == 1
      assert hd(response["data"])["id"] == cluster2.id
    end

    test "sorts by node_count", %{conn: conn} do
      expect(NexmakerMock, :create_network, 2, fn _, _ -> {:ok, %{}} end)

      cluster1 = cluster_fixture(%{ipv4_range: "100.64.1.0/24"})
      cluster2 = cluster_fixture(%{ipv4_range: "100.64.2.0/24"})

      # Add 2 nodes to cluster2, 1 to cluster1
      node_fixture(%{cluster_id: cluster1.id})
      node_fixture(%{cluster_id: cluster2.id})
      node_fixture(%{cluster_id: cluster2.id})

      # Sort by node_count descending (cluster2 should be first)
      conn = get(conn, ~p"/api/clusters?sort=node_count:desc")
      response = json_response(conn, 200)

      assert hd(response["data"])["id"] == cluster2.id
      assert hd(response["data"])["node_count"] == 2
    end
  end

  describe "show" do
    test "shows a specific cluster", %{conn: conn} do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)
      cluster = cluster_fixture()

      conn = get(conn, ~p"/api/clusters/#{cluster.id}")
      assert json_response(conn, 200)["data"]["id"] == cluster.id
      assert json_response(conn, 200)["data"]["ipv4_range"] == cluster.ipv4_range
      assert json_response(conn, 200)["data"]["node_count"] == 0
    end

    test "returns 404 for non-existent cluster", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/clusters/#{non_existent_id}")
      assert json_response(conn, 404)
    end
  end

  describe "create" do
    test "creates cluster with explicit ipv4_range", %{conn: conn} do
      expect(NexmakerMock, :create_network, fn network_name, params ->
        assert network_name =~ ~r/^cluster-/
        assert params.addressrange == "100.64.50.0/24"
        {:ok, %{}}
      end)

      cluster_params = %{ipv4_range: "100.64.50.0/24"}

      conn = post(conn, ~p"/api/clusters", cluster: cluster_params)
      assert %{"id" => id} = json_response(conn, 201)["data"]

      conn = get(conn, ~p"/api/clusters/#{id}")
      assert json_response(conn, 200)["data"]["ipv4_range"] == "100.64.50.0/24"
    end

    test "creates cluster with auto-generated ipv4_range", %{conn: conn} do
      expect(NexmakerMock, :create_network, fn _, params ->
        assert params.addressrange =~ ~r/^100\.64\.\d+\.0\/24$/
        {:ok, %{}}
      end)

      conn = post(conn, ~p"/api/clusters", cluster: %{})
      assert %{"id" => id} = json_response(conn, 201)["data"]
      assert json_response(conn, 201)["data"]["ipv4_range"] =~ ~r/^100\.64\.\d+\.0\/24$/

      # Verify location header
      assert Enum.any?(conn.resp_headers, fn {key, value} ->
               key == "location" && value =~ ~r"/api/clusters/#{id}"
             end)
    end

    test "creates cluster with explicit ID", %{conn: conn} do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)

      explicit_id = Ecto.UUID.generate()
      cluster_params = %{id: explicit_id, ipv4_range: "100.64.51.0/24"}

      conn = post(conn, ~p"/api/clusters", cluster: cluster_params)
      assert json_response(conn, 201)["data"]["id"] == explicit_id
    end

    test "returns error for invalid ipv4_range", %{conn: conn} do
      cluster_params = %{ipv4_range: "invalid"}

      conn = post(conn, ~p"/api/clusters", cluster: cluster_params)
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "returns error for duplicate ipv4_range", %{conn: conn} do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)
      cluster = cluster_fixture(%{ipv4_range: "100.64.60.0/24"})

      cluster_params = %{ipv4_range: cluster.ipv4_range}

      conn = post(conn, ~p"/api/clusters", cluster: cluster_params)
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "returns error for private IP range", %{conn: conn} do
      cluster_params = %{ipv4_range: "192.168.1.0/24"}

      conn = post(conn, ~p"/api/clusters", cluster: cluster_params)
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "rolls back on Netmaker network creation failure", %{conn: conn} do
      expect(NexmakerMock, :create_network, fn _, _ ->
        {:error, "Netmaker error"}
      end)

      cluster_params = %{ipv4_range: "100.64.70.0/24"}

      conn = post(conn, ~p"/api/clusters", cluster: cluster_params)
      # Should return error since transaction rolled back
      assert json_response(conn, 500) || json_response(conn, 422)
    end
  end

  describe "delete" do
    test "deletes chosen cluster", %{conn: conn} do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)

      expect(NexmakerMock, :delete_network, fn network_name ->
        assert network_name =~ ~r/^cluster-/
        {:ok, %{}}
      end)

      cluster = cluster_fixture()

      conn = delete(conn, ~p"/api/clusters/#{cluster.id}")
      assert response(conn, 204)

      # Verify it's deleted
      conn = get(conn, ~p"/api/clusters/#{cluster.id}")
      assert json_response(conn, 404)
    end

    test "returns 404 for non-existent cluster", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = delete(conn, ~p"/api/clusters/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "returns error when deleting cluster with nodes", %{conn: conn} do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)
      cluster = cluster_fixture()

      # Create a node in this cluster
      node_fixture(%{cluster_id: cluster.id})

      conn = delete(conn, ~p"/api/clusters/#{cluster.id}")
      # Fallback controller handles :cluster_not_empty error with inspect/1
      response = json_response(conn, 422)
      assert response["error"] == ":cluster_not_empty"
    end

    test "rolls back on Netmaker network deletion failure", %{conn: conn} do
      expect(NexmakerMock, :create_network, fn _, _ -> {:ok, %{}} end)

      expect(NexmakerMock, :delete_network, fn _ ->
        {:error, "Netmaker deletion error"}
      end)

      cluster = cluster_fixture()

      conn = delete(conn, ~p"/api/clusters/#{cluster.id}")
      # Should return error since transaction rolled back
      assert json_response(conn, 500) || json_response(conn, 422)

      # Cluster should still exist
      conn = get(conn, ~p"/api/clusters/#{cluster.id}")
      assert json_response(conn, 200)
    end
  end
end
