# edge_admin/test/edge_admin/sort_test.exs
defmodule EdgeAdmin.SortTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Sort

  test "parses ascending and descending sort fields into Flop parameters" do
    assert {:ok, %{order_by: ["name", "status", "inserted_at"], order_directions: [:desc, :asc, :desc]}} =
             Sort.parse("-name,status,-inserted_at")
  end

  test "rejects malformed sort expressions" do
    for sort <- ["", "name,", ",name", "name:desc", "name, status", "--name", "1name"] do
      assert {:error, :invalid_sort} = Sort.parse(sort)
    end
  end
end
