# edge_admin/test/edge_admin_web/schemas/path_params_test.exs
defmodule EdgeAdminWeb.Schemas.PathParamsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Naming
  alias EdgeAdminWeb.Schemas.PathParams
  alias OpenApiSpex.Schema

  # ---------------------------------------------------------------------------
  # uuid/2 — UUID path parameter
  # ---------------------------------------------------------------------------

  describe "uuid/2" do
    test "produces a {name, opts} tuple with :path location" do
      assert {:id, opts} = PathParams.uuid(:id, "Node ID")

      assert opts[:in] == :path
      assert opts[:description] == "Node ID"
    end

    test "schema is a UUID-formatted string" do
      {:id, opts} = PathParams.uuid(:id, "X")

      assert opts[:schema] == %Schema{type: :string, format: :uuid}
    end

    test "passes the name through unchanged (used for nested resources too)" do
      {:node_id, _opts} = PathParams.uuid(:node_id, "Parent node ID")
      {:command_id, _opts} = PathParams.uuid(:command_id, "Command ID")
    end
  end

  # ---------------------------------------------------------------------------
  # cluster_name/2 — DNS-style charset, max 24 chars (sourced from Naming)
  # ---------------------------------------------------------------------------

  describe "cluster_name/2" do
    test "produces a {name, opts} tuple with :path location" do
      assert {:name, opts} = PathParams.cluster_name(:name, "Cluster name")

      assert opts[:in] == :path
      assert opts[:description] == "Cluster name"
    end

    test "schema sources its pattern + maxLength from EdgeAdmin.Naming (cross-module contract)" do
      # Critical: when Naming tightens cluster_name_max_length or the regex,
      # this builder must reflect it. Pinning the source-of-truth lookup
      # surfaces drift if anyone hardcodes a different value.
      {:name, opts} = PathParams.cluster_name(:name, "X")

      assert opts[:schema] == %Schema{
               type: :string,
               pattern: Naming.cluster_name_pattern(),
               maxLength: Naming.cluster_name_max_length()
             }
    end
  end
end
