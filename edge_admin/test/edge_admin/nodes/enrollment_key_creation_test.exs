# edge_admin/test/edge_admin/nodes/enrollment_key_creation_test.exs
defmodule EdgeAdmin.Nodes.EnrollmentKeyCreationTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Repo

  test "binds the enrollment key blob to its cluster name" do
    cluster =
      Repo.insert!(%Cluster{
        id: Ecto.UUID.generate(),
        name: "cluster-enrollment-key-test",
        ipv4_range: "100.64.11.0/24",
        ipv6_range: "fd7a:91c2:4e8b:11::/64"
      })

    assert {:ok, enrollment_key} = Nodes.create_enrollment_key(cluster)
    assert {:ok, json} = Base.decode64(enrollment_key.key, padding: false)
    assert {:ok, %{"cluster_name" => cluster_name}} = JSON.decode(json)
    assert cluster_name == cluster.name
  end
end
