# edge_admin/test/edge_admin/filtering_pagination_test.exs
defmodule EdgeAdmin.FilteringPaginationTest do
  use EdgeAdmin.DataCase, async: true

  alias EdgeAdmin.FilteringPagination
  alias EdgeAdmin.Nodes.Node

  # Test data setup
  defp create_test_nodes do
    nodes = [
      %{id: "00000000-0000-0000-0000-000000000001", status: "online", id_type: "machine_id", vpn_ip: "100.64.0.1"},
      %{id: "00000000-0000-0000-0000-000000000002", status: "offline", id_type: "hardware_id", vpn_ip: "100.64.0.2"},
      %{id: "00000000-0000-0000-0000-000000000003", status: "online", id_type: "temporary_id", vpn_ip: "100.64.0.3"},
      %{id: "00000000-0000-0000-0000-000000000004", status: "unknown", id_type: "machine_id", vpn_ip: "100.64.1.1"},
      %{id: "00000000-0000-0000-0000-000000000005", status: "online", id_type: "hardware_id", vpn_ip: "100.65.0.1"}
    ]

    Enum.each(nodes, fn attrs ->
      %Node{}
      |> Node.changeset(attrs)
      |> Repo.insert!()
    end)

    nodes
  end

  describe "paginate/3 basic functionality" do
    test "returns all data with default pagination" do
      create_test_nodes()

      result = FilteringPagination.paginate(Node, %{}, repo: Repo)

      assert %FilteringPagination{} = result
      assert length(result.data) == 5
      assert result.page == 1
      assert result.page_size == 20
      assert result.total == 5
      assert result.total_pages == 1
      assert result.has_next == false
      assert result.has_prev == false
      assert result.filters == %{}
      assert result.sort == []
    end

    test "handles empty dataset" do
      result = FilteringPagination.paginate(Node, %{}, repo: Repo)

      assert result.data == []
      assert result.total == 0
      assert result.total_pages == 0
      assert result.has_next == false
      assert result.has_prev == false
    end

    test "handles custom page size" do
      create_test_nodes()

      result = FilteringPagination.paginate(Node, %{"page_size" => "2"}, repo: Repo)

      assert length(result.data) == 2
      assert result.page_size == 2
      assert result.total_pages == 3
      assert result.has_next == true
      assert result.has_prev == false
    end

    test "handles pagination across multiple pages" do
      create_test_nodes()

      # Page 1
      page1 = FilteringPagination.paginate(Node, %{"page" => "1", "page_size" => "2"}, repo: Repo)
      assert page1.page == 1
      assert length(page1.data) == 2
      assert page1.has_next == true
      assert page1.has_prev == false

      # Page 2
      page2 = FilteringPagination.paginate(Node, %{"page" => "2", "page_size" => "2"}, repo: Repo)
      assert page2.page == 2
      assert length(page2.data) == 2
      assert page2.has_next == true
      assert page2.has_prev == true

      # Page 3 (last page)
      page3 = FilteringPagination.paginate(Node, %{"page" => "3", "page_size" => "2"}, repo: Repo)
      assert page3.page == 3
      assert length(page3.data) == 1
      assert page3.has_next == false
      assert page3.has_prev == true
    end
  end

  describe "parameter parsing" do
    test "handles invalid page numbers" do
      create_test_nodes()

      # Negative page
      result = FilteringPagination.paginate(Node, %{"page" => "-1"}, repo: Repo)
      assert result.page == 1

      # Zero page
      result = FilteringPagination.paginate(Node, %{"page" => "0"}, repo: Repo)
      assert result.page == 1

      # Invalid string
      result = FilteringPagination.paginate(Node, %{"page" => "invalid"}, repo: Repo)
      assert result.page == 1

      # Very large page (beyond available data)
      result = FilteringPagination.paginate(Node, %{"page" => "999"}, repo: Repo)
      assert result.page == 999
      assert result.data == []
    end

    test "handles invalid page sizes" do
      create_test_nodes()

      # Negative page size - should default to 20
      result = FilteringPagination.paginate(Node, %{"page_size" => "-5"}, repo: Repo)
      assert result.page_size == 20

      # Zero page size - should default to 20
      result = FilteringPagination.paginate(Node, %{"page_size" => "0"}, repo: Repo)
      assert result.page_size == 20

      # Page size exceeding max - should cap at 100
      result = FilteringPagination.paginate(Node, %{"page_size" => "150"}, repo: Repo)
      assert result.page_size == 100

      # Invalid string - should default to 20
      result = FilteringPagination.paginate(Node, %{"page_size" => "invalid"}, repo: Repo)
      assert result.page_size == 20
    end

    test "handles integer parameters" do
      create_test_nodes()

      result = FilteringPagination.paginate(Node, %{"page" => 2, "page_size" => 3}, repo: Repo)
      assert result.page == 2
      assert result.page_size == 3
    end
  end

  describe "filtering functionality" do
    setup do
      create_test_nodes()
      :ok
    end

    test "filters by exact match" do
      result = FilteringPagination.paginate(
        Node,
        %{"status" => "online"},
        filterable_fields: [:status],
        repo: Repo
      )

      assert length(result.data) == 3
      assert result.filters == %{"status" => "online"}
      Enum.each(result.data, fn node -> assert node.status == "online" end)
    end

    test "filters by multiple fields" do
      result = FilteringPagination.paginate(
        Node,
        %{"status" => "online", "id_type" => "machine_id"},
        filterable_fields: [:status, :id_type],
        repo: Repo
      )

      assert length(result.data) == 1
      assert result.filters == %{"status" => "online", "id_type" => "machine_id"}
      node = hd(result.data)
      assert node.status == "online"
      assert node.id_type == "machine_id"
    end

    test "filters with wildcard patterns" do
      result = FilteringPagination.paginate(
        Node,
        %{"vpn_ip" => "100.64.*"},
        filterable_fields: [:vpn_ip],
        repo: Repo
      )

      assert length(result.data) == 4
      Enum.each(result.data, fn node ->
        assert String.starts_with?(node.vpn_ip, "100.64.")
      end)
    end

    test "filters with comma-separated values (IN operation)" do
      result = FilteringPagination.paginate(
        Node,
        %{"status" => "online,offline"},
        filterable_fields: [:status],
        repo: Repo
      )

      assert length(result.data) == 4
      Enum.each(result.data, fn node ->
        assert node.status in ["online", "offline"]
      end)
    end

    test "ignores non-filterable fields" do
      result = FilteringPagination.paginate(
        Node,
        %{"status" => "online", "non_existent_field" => "value"},
        filterable_fields: [:status],
        repo: Repo
      )

      assert length(result.data) == 3
      # Only the filterable field should be in filters
      assert result.filters == %{"status" => "online"}
    end

    test "ignores empty and nil filter values" do
      result = FilteringPagination.paginate(
        Node,
        %{"status" => "online", "id_type" => "", "vpn_ip" => nil},
        filterable_fields: [:status, :id_type, :vpn_ip],
        repo: Repo
      )

      assert length(result.data) == 3
      # Only non-empty values should be in filters
      assert result.filters == %{"status" => "online"}
    end
  end

  describe "sorting functionality" do
    setup do
      # Create nodes with specific timestamps for sorting tests
      nodes = [
        %{id: "00000000-0000-0000-0000-000000000001", status: "online", vpn_ip: "100.64.0.3"},
        %{id: "00000000-0000-0000-0000-000000000002", status: "offline", vpn_ip: "100.64.0.1"},
        %{id: "00000000-0000-0000-0000-000000000003", status: "online", vpn_ip: "100.64.0.2"}
      ]

      # Insert with slight delays to ensure different timestamps
      Enum.each(nodes, fn attrs ->
        %Node{}
        |> Node.changeset(attrs)
        |> Repo.insert!()

        :timer.sleep(1)  # Ensure different timestamps
      end)

      :ok
    end

    test "sorts by single field ascending" do
      result = FilteringPagination.paginate(
        Node,
        %{"sort" => "vpn_ip:asc"},
        sortable_fields: [:vpn_ip],
        repo: Repo
      )

      vpn_ips = Enum.map(result.data, & &1.vpn_ip)
      assert vpn_ips == ["100.64.0.1", "100.64.0.2", "100.64.0.3"]
      assert result.sort == [{:vpn_ip, :asc}]
    end

    test "sorts by single field descending" do
      result = FilteringPagination.paginate(
        Node,
        %{"sort" => "vpn_ip:desc"},
        sortable_fields: [:vpn_ip],
        repo: Repo
      )

      vpn_ips = Enum.map(result.data, & &1.vpn_ip)
      assert vpn_ips == ["100.64.0.3", "100.64.0.2", "100.64.0.1"]
      assert result.sort == [{:vpn_ip, :desc}]
    end

    test "sorts by multiple fields" do
      result = FilteringPagination.paginate(
        Node,
        %{"sort" => "status:desc,vpn_ip:asc"},
        sortable_fields: [:status, :vpn_ip],
        repo: Repo
      )

      # Should sort by status desc first (online before offline), then by vpn_ip asc
      expected_ips = ["100.64.0.2", "100.64.0.3", "100.64.0.1"]  # offline first, then online sorted by IP
      actual_ips = Enum.map(result.data, & &1.vpn_ip)
      assert actual_ips == expected_ips
      assert result.sort == [{:status, :desc}, {:vpn_ip, :asc}]
    end

    test "defaults to ascending when direction not specified" do
      result = FilteringPagination.paginate(
        Node,
        %{"sort" => "vpn_ip"},
        sortable_fields: [:vpn_ip],
        repo: Repo
      )

      vpn_ips = Enum.map(result.data, & &1.vpn_ip)
      assert vpn_ips == ["100.64.0.1", "100.64.0.2", "100.64.0.3"]
      assert result.sort == [{:vpn_ip, :asc}]
    end

    test "ignores non-sortable fields" do
      result = FilteringPagination.paginate(
        Node,
        %{"sort" => "vpn_ip:asc,non_existent:desc"},
        sortable_fields: [:vpn_ip],
        repo: Repo
      )

      # Should only sort by the sortable field
      assert result.sort == [{:vpn_ip, :asc}]
    end

    test "uses default sort when no sort parameter provided" do
      result = FilteringPagination.paginate(
        Node,
        %{},
        sortable_fields: [:vpn_ip, :status],
        default_sort: "vpn_ip:desc",
        repo: Repo
      )

      vpn_ips = Enum.map(result.data, & &1.vpn_ip)
      assert vpn_ips == ["100.64.0.3", "100.64.0.2", "100.64.0.1"]
      assert result.sort == [{:vpn_ip, :desc}]
    end

    test "uses default sort as keyword list" do
      result = FilteringPagination.paginate(
        Node,
        %{},
        sortable_fields: [:status, :vpn_ip],
        default_sort: [status: :asc, vpn_ip: :desc],
        repo: Repo
      )

      assert result.sort == [{:status, :asc}, {:vpn_ip, :desc}]
    end

    test "handles invalid sort parameters gracefully" do
      result = FilteringPagination.paginate(
        Node,
        %{"sort" => "invalid_field:invalid_direction,vpn_ip:asc"},
        sortable_fields: [:vpn_ip],
        repo: Repo
      )

      # Should ignore invalid parts and only use valid ones
      assert result.sort == [{:vpn_ip, :asc}]
    end
  end

  describe "parse_sort/3 function" do
    test "parses single field with direction" do
      result = FilteringPagination.parse_sort("name:asc", [], [:name, :status])
      assert result == [{:name, :asc}]

      result = FilteringPagination.parse_sort("status:desc", [], [:name, :status])
      assert result == [{:status, :desc}]
    end

    test "parses multiple fields with directions" do
      result = FilteringPagination.parse_sort("name:asc,status:desc", [], [:name, :status])
      assert result == [{:name, :asc}, {:status, :desc}]
    end

    test "defaults to ascending when no direction specified" do
      result = FilteringPagination.parse_sort("name,status:desc", [], [:name, :status])
      assert result == [{:name, :asc}, {:status, :desc}]
    end

    test "filters out non-sortable fields" do
      result = FilteringPagination.parse_sort("name:asc,invalid:desc", [], [:name])
      assert result == [{:name, :asc}]
    end

    test "handles empty sort parameter" do
      result = FilteringPagination.parse_sort("", [], [:name, :status])
      assert result == []
    end

    test "handles nil sort parameter with default" do
      result = FilteringPagination.parse_sort(nil, "name:desc", [:name, :status])
      assert result == [{:name, :desc}]

      result = FilteringPagination.parse_sort(nil, [name: :asc, status: :desc], [:name, :status])
      assert result == [{:name, :asc}, {:status, :desc}]
    end

    test "handles invalid field names gracefully" do
      result = FilteringPagination.parse_sort("nonexistent:asc", [], [:name])
      assert result == []
    end

    test "handles whitespace in sort parameter" do
      result = FilteringPagination.parse_sort(" name:asc , status:desc ", [], [:name, :status])
      assert result == [{:name, :asc}, {:status, :desc}]
    end
  end

  describe "combined filtering and sorting" do
    setup do
      create_test_nodes()
      :ok
    end

    test "applies both filtering and sorting" do
      result = FilteringPagination.paginate(
        Node,
        %{"status" => "online", "sort" => "vpn_ip:desc"},
        filterable_fields: [:status],
        sortable_fields: [:vpn_ip],
        repo: Repo
      )

      assert length(result.data) == 3
      assert result.filters == %{"status" => "online"}
      assert result.sort == [{:vpn_ip, :desc}]

      # All nodes should have status "online" and be sorted by vpn_ip desc
      Enum.each(result.data, fn node -> assert node.status == "online" end)
      vpn_ips = Enum.map(result.data, & &1.vpn_ip)
      assert vpn_ips == Enum.sort(vpn_ips, :desc)
    end

    test "applies filtering, sorting, and pagination together" do
      result = FilteringPagination.paginate(
        Node,
        %{"status" => "online", "sort" => "vpn_ip:asc", "page" => "1", "page_size" => "2"},
        filterable_fields: [:status],
        sortable_fields: [:vpn_ip],
        repo: Repo
      )

      assert length(result.data) == 2
      assert result.page == 1
      assert result.page_size == 2
      assert result.total == 3  # Total online nodes
      assert result.total_pages == 2
      assert result.has_next == true
      assert result.filters == %{"status" => "online"}
      assert result.sort == [{:vpn_ip, :asc}]
    end
  end

  describe "configuration options" do
    test "respects custom default page size" do
      result = FilteringPagination.paginate(
        Node,
        %{},
        page_size: 5,
        repo: Repo
      )

      assert result.page_size == 5
    end

    test "respects custom max page size" do
      result = FilteringPagination.paginate(
        Node,
        %{"page_size" => "200"},
        max_page_size: 50,
        repo: Repo
      )

      assert result.page_size == 50
    end

    test "works with custom repo option" do
      # This test just ensures the repo option is passed through correctly
      result = FilteringPagination.paginate(
        Node,
        %{},
        repo: EdgeAdmin.Repo
      )

      assert %FilteringPagination{} = result
    end
  end

  describe "edge cases" do
    test "handles extremely large page numbers" do
      create_test_nodes()

      result = FilteringPagination.paginate(
        Node,
        %{"page" => "999999"},
        repo: Repo
      )

      assert result.page == 999999
      assert result.data == []
      assert result.total == 5
      assert result.has_next == false
      assert result.has_prev == true
    end

    test "handles total_pages calculation correctly" do
      create_test_nodes()

      # 5 items with page_size 2 should give 3 pages
      result = FilteringPagination.paginate(
        Node,
        %{"page_size" => "2"},
        repo: Repo
      )

      assert result.total == 5
      assert result.total_pages == 3
    end

    test "handles zero total items" do
      result = FilteringPagination.paginate(
        Node,
        %{"status" => "nonexistent"},
        filterable_fields: [:status],
        repo: Repo
      )

      assert result.total == 0
      assert result.total_pages == 0
      assert result.has_next == false
      assert result.has_prev == false
    end
  end
end
