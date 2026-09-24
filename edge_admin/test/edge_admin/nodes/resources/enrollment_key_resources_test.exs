# edge_admin/test/edge_admin/nodes/resources/enrollment_key_resources_test.exs
defmodule EdgeAdmin.Nodes.Resources.EnrollmentKeyResourcesTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Resources.EnrollmentKeyResources

  test "builds an enrollment blob bound to a cluster and configured admin URLs" do
    admin_urls = ["https://admin-a.example", "https://admin-b.example"]
    cluster_name = "production"
    nonce = "fixed-nonce"

    key = EnrollmentKeyResources.build_key_blob(admin_urls, cluster_name, nonce)

    refute String.ends_with?(key, "=")
    assert {:ok, json} = Base.decode64(key, padding: false)

    assert {:ok,
            %{
              "admin_urls" => ^admin_urls,
              "cluster_name" => ^cluster_name,
              "nonce" => ^nonce
            }} = JSON.decode(json)
  end
end
