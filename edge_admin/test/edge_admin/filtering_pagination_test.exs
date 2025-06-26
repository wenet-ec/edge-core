# edge_admin/test/edge_admin/filtering_pagination_test.exs
defmodule EdgeAdmin.FilteringPaginationTest do
  use EdgeAdmin.DataCase, async: true

  alias EdgeAdmin.FilteringPagination
  alias EdgeAdmin.Nodes.Node

  # Test data setup
  defp create_test_nodes do
    nodes = [
      %{
        id: "00000000-0000-0000-0000-000000000001",
        status: "online",
        id_type: "machine_id",
        vpn_ip: "100.64.0.1"
      },
      %{
        id: "00000000-0000-0000-0000-000000000002",
        status: "offline",
        id_type: "hardware_id",
        vpn_ip: "100.64.0.2"
      },
      %{
        id: "00000000-0000-0000-0000-000000000003",
        status: "online",
        id_type: "temporary_id",
        vpn_ip: "100.64.0.3"
      },
      %{
        id: "00000000-0000-0000-0000-000000000004",
        status: "offline",
        id_type: "machine_id",
        vpn_ip: "100.64.1.1"
      },
      %{
        id: "00000000-0000-0000-0000-000000000005",
        status: "online",
        id_type: "hardware_id",
        vpn_ip: "100.65.0.1"
      }
    ]

    Enum.each(nodes, fn attrs ->
      %Node{}
      |> Node.changeset(attrs)
      |> Repo.insert!()
    end)

    nodes
  end

  describe "core pagination functionality" do
    test "basic pagination with defaults and custom page sizes" do
      create_test_nodes()

      # Default pagination
      result = FilteringPagination.paginate(Node, %{}, repo: Repo)
      assert %FilteringPagination{} = result
      assert length(result.data) == 5
      assert result.page == 1
      assert result.page_size == 20
      assert result.total == 5
      assert result.total_pages == 1
      assert result.has_next == false
      assert result.has_prev == false

      # Custom page size
      result = FilteringPagination.paginate(Node, %{"page_size" => "2"}, repo: Repo)
      assert length(result.data) == 2
      assert result.page_size == 2
      assert result.total_pages == 3
      assert result.has_next == true
    end

    test "pagination across multiple pages" do
      create_test_nodes()

      # Test page navigation
      page1 = FilteringPagination.paginate(Node, %{"page" => "1", "page_size" => "2"}, repo: Repo)
      assert page1.page == 1
      assert page1.has_next == true
      assert page1.has_prev == false

      page2 = FilteringPagination.paginate(Node, %{"page" => "2", "page_size" => "2"}, repo: Repo)
      assert page2.page == 2
      assert page2.has_next == true
      assert page2.has_prev == true

      page3 = FilteringPagination.paginate(Node, %{"page" => "3", "page_size" => "2"}, repo: Repo)
      assert page3.page == 3
      assert length(page3.data) == 1
      assert page3.has_next == false
      assert page3.has_prev == true
    end

    test "parameter validation and edge cases" do
      create_test_nodes()

      # Invalid page numbers default to 1
      result = FilteringPagination.paginate(Node, %{"page" => "-1"}, repo: Repo)
      assert result.page == 1

      result = FilteringPagination.paginate(Node, %{"page" => "invalid"}, repo: Repo)
      assert result.page == 1

      # Large page numbers work but return empty data
      result = FilteringPagination.paginate(Node, %{"page" => "999"}, repo: Repo)
      assert result.page == 999
      assert result.data == []

      # Invalid page sizes use defaults/limits
      result = FilteringPagination.paginate(Node, %{"page_size" => "-5"}, repo: Repo)
      assert result.page_size == 20

      result = FilteringPagination.paginate(Node, %{"page_size" => "150"}, repo: Repo)
      assert result.page_size == 100
    end

    test "empty dataset handling" do
      result = FilteringPagination.paginate(Node, %{}, repo: Repo)
      assert result.data == []
      assert result.total == 0
      assert result.total_pages == 0
      assert result.has_next == false
      assert result.has_prev == false
    end
  end

  describe "filtering functionality" do
    setup do
      create_test_nodes()
      :ok
    end

    test "exact match and multiple field filtering" do
      # Single field filtering
      result =
        FilteringPagination.paginate(
          Node,
          %{"status" => "online"},
          filterable_fields: [:status],
          repo: Repo
        )

      assert length(result.data) == 3
      assert result.filters == %{"status" => "online"}
      Enum.each(result.data, fn node -> assert node.status == "online" end)

      # Multiple field filtering
      result =
        FilteringPagination.paginate(
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

    test "advanced filtering patterns" do
      # Wildcard filtering
      result =
        FilteringPagination.paginate(
          Node,
          %{"vpn_ip" => "100.64.*"},
          filterable_fields: [:vpn_ip],
          repo: Repo
        )

      assert length(result.data) == 4

      Enum.each(result.data, fn node ->
        assert String.starts_with?(node.vpn_ip, "100.64.")
      end)

      # IN operation (comma-separated)
      result =
        FilteringPagination.paginate(
          Node,
          %{"status" => "online"},
          filterable_fields: [:status],
          repo: Repo
        )

      assert length(result.data) == 3

      Enum.each(result.data, fn node ->
        assert node.status in ["online"]
      end)
    end

    test "filtering validation and edge cases" do
      # Non-filterable fields are ignored
      result =
        FilteringPagination.paginate(
          Node,
          %{"status" => "online", "non_existent_field" => "value"},
          filterable_fields: [:status],
          repo: Repo
        )

      assert length(result.data) == 3
      assert result.filters == %{"status" => "online"}

      # Empty/nil values are ignored
      result =
        FilteringPagination.paginate(
          Node,
          %{"status" => "online", "id_type" => "", "vpn_ip" => nil},
          filterable_fields: [:status, :id_type, :vpn_ip],
          repo: Repo
        )

      assert result.filters == %{"status" => "online"}
    end
  end

  describe "sorting functionality" do
    setup do
      # Create nodes with known VPN IPs for predictable sorting
      nodes = [
        %{id: "00000000-0000-0000-0000-000000000001", status: "online", vpn_ip: "100.64.0.3"},
        %{id: "00000000-0000-0000-0000-000000000002", status: "offline", vpn_ip: "100.64.0.1"},
        %{id: "00000000-0000-0000-0000-000000000003", status: "online", vpn_ip: "100.64.0.2"}
      ]

      Enum.each(nodes, fn attrs ->
        %Node{}
        |> Node.changeset(attrs)
        |> Repo.insert!()

        # Ensure different timestamps
        :timer.sleep(1)
      end)

      :ok
    end

    test "single field sorting" do
      # Ascending
      result =
        FilteringPagination.paginate(
          Node,
          %{"sort" => "vpn_ip:asc"},
          sortable_fields: [:vpn_ip],
          repo: Repo
        )

      vpn_ips = Enum.map(result.data, & &1.vpn_ip)
      assert vpn_ips == ["100.64.0.1", "100.64.0.2", "100.64.0.3"]
      assert result.sort == [{:vpn_ip, :asc}]

      # Descending
      result =
        FilteringPagination.paginate(
          Node,
          %{"sort" => "vpn_ip:desc"},
          sortable_fields: [:vpn_ip],
          repo: Repo
        )

      vpn_ips = Enum.map(result.data, & &1.vpn_ip)
      assert vpn_ips == ["100.64.0.3", "100.64.0.2", "100.64.0.1"]
    end

    test "multi-field sorting and defaults" do
      # Multiple fields
      result =
        FilteringPagination.paginate(
          Node,
          %{"sort" => "status:desc,vpn_ip:asc"},
          sortable_fields: [:status, :vpn_ip],
          repo: Repo
        )

      assert result.sort == [{:status, :desc}, {:vpn_ip, :asc}]

      # Default to ascending when no direction
      result =
        FilteringPagination.paginate(
          Node,
          %{"sort" => "vpn_ip"},
          sortable_fields: [:vpn_ip],
          repo: Repo
        )

      assert result.sort == [{:vpn_ip, :asc}]

      # Default sort when no parameter provided
      result =
        FilteringPagination.paginate(
          Node,
          %{},
          sortable_fields: [:vpn_ip],
          default_sort: "vpn_ip:desc",
          repo: Repo
        )

      assert result.sort == [{:vpn_ip, :desc}]
    end

    test "sorting validation" do
      # Non-sortable fields are ignored
      result =
        FilteringPagination.paginate(
          Node,
          %{"sort" => "vpn_ip:asc,non_existent:desc"},
          sortable_fields: [:vpn_ip],
          repo: Repo
        )

      assert result.sort == [{:vpn_ip, :asc}]

      # Invalid sort parameters handled gracefully
      result =
        FilteringPagination.paginate(
          Node,
          %{"sort" => "invalid_field:invalid_direction,vpn_ip:asc"},
          sortable_fields: [:vpn_ip],
          repo: Repo
        )

      assert result.sort == [{:vpn_ip, :asc}]
    end
  end

  describe "parse_sort/3 utility function" do
    test "core parsing functionality" do
      # Single field
      result = FilteringPagination.parse_sort("name:asc", [], [:name, :status])
      assert result == [{:name, :asc}]

      # Multiple fields
      result = FilteringPagination.parse_sort("name:asc,status:desc", [], [:name, :status])
      assert result == [{:name, :asc}, {:status, :desc}]

      # Default direction
      result = FilteringPagination.parse_sort("name,status:desc", [], [:name, :status])
      assert result == [{:name, :asc}, {:status, :desc}]

      # Non-sortable fields filtered out
      result = FilteringPagination.parse_sort("name:asc,invalid:desc", [], [:name])
      assert result == [{:name, :asc}]
    end

    test "parse_sort edge cases" do
      # Empty parameter
      result = FilteringPagination.parse_sort("", [], [:name, :status])
      assert result == []

      # Nil with default
      result = FilteringPagination.parse_sort(nil, "name:desc", [:name, :status])
      assert result == [{:name, :desc}]

      result = FilteringPagination.parse_sort(nil, [name: :asc, status: :desc], [:name, :status])
      assert result == [{:name, :asc}, {:status, :desc}]

      # Whitespace handling
      result = FilteringPagination.parse_sort(" name:asc , status:desc ", [], [:name, :status])
      assert result == [{:name, :asc}, {:status, :desc}]
    end
  end

  describe "integration scenarios" do
    setup do
      create_test_nodes()
      :ok
    end

    test "combined filtering, sorting, and pagination" do
      result =
        FilteringPagination.paginate(
          Node,
          %{"status" => "online", "sort" => "vpn_ip:desc", "page" => "1", "page_size" => "2"},
          filterable_fields: [:status],
          sortable_fields: [:vpn_ip],
          repo: Repo
        )

      assert length(result.data) == 2
      assert result.page == 1
      assert result.page_size == 2
      # Total online nodes
      assert result.total == 3
      assert result.total_pages == 2
      assert result.has_next == true
      assert result.filters == %{"status" => "online"}
      assert result.sort == [{:vpn_ip, :desc}]

      # Verify filtering and sorting were applied
      Enum.each(result.data, fn node -> assert node.status == "online" end)
      vpn_ips = Enum.map(result.data, & &1.vpn_ip)
      assert vpn_ips == Enum.sort(vpn_ips, :desc)
    end

    test "configuration options and edge cases" do
      # Custom page size and max limits
      result = FilteringPagination.paginate(Node, %{}, page_size: 5, repo: Repo)
      assert result.page_size == 5

      result =
        FilteringPagination.paginate(Node, %{"page_size" => "200"}, max_page_size: 50, repo: Repo)

      assert result.page_size == 50

      # Zero total items
      result =
        FilteringPagination.paginate(
          Node,
          %{"status" => "nonexistent"},
          filterable_fields: [:status],
          repo: Repo
        )

      assert result.total == 0
      assert result.total_pages == 0
      assert result.has_next == false
      assert result.has_prev == false

      # Total pages calculation (5 items, page_size 2 = 3 pages)
      result = FilteringPagination.paginate(Node, %{"page_size" => "2"}, repo: Repo)
      assert result.total == 5
      assert result.total_pages == 3
    end
  end
end
