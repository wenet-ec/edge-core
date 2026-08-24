# edge_admin/test/edge_admin/nodes/resources/clusters_test.exs
defmodule EdgeAdmin.Nodes.Resources.ClustersTest do
  use ExUnit.Case, async: false

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Resources.Clusters

  setup do
    previous_cluster = Elixir.Application.get_env(:edge_admin, :default_cluster_name)

    on_exit(fn ->
      case previous_cluster do
        nil -> Elixir.Application.delete_env(:edge_admin, :default_cluster_name)
        value -> Elixir.Application.put_env(:edge_admin, :default_cluster_name, value)
      end
    end)

    :ok
  end

  test "returns the configured default cluster name" do
    Elixir.Application.put_env(:edge_admin, :default_cluster_name, "production")

    assert Clusters.default_cluster_name() == "production"
    assert Nodes.default_cluster_name() == "production"
  end

  test "returns nil when the default cluster is unset" do
    Elixir.Application.delete_env(:edge_admin, :default_cluster_name)

    assert Clusters.default_cluster_name() == nil
    assert Nodes.default_cluster_name() == nil
  end
end
