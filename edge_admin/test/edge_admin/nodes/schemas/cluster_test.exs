# edge_admin/test/edge_admin/nodes/schemas/cluster_test.exs
defmodule EdgeAdmin.Nodes.Schemas.ClusterTest do
  use ExUnit.Case, async: true

  alias Ecto.Association.NotLoaded
  alias EdgeAdmin.Nodes.Schemas.Cluster

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  defp build_changeset(attrs) do
    Cluster.changeset(%Cluster{}, attrs)
  end

  defp apply(attrs) do
    attrs |> build_changeset() |> Ecto.Changeset.apply_action(:insert)
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — name validation
  # ---------------------------------------------------------------------------

  describe "changeset/2 — name validation" do
    test "valid lowercase name passes" do
      assert {:ok, cluster} = apply(%{"name" => "prod", "ipv4_range" => "100.64.1.0/24"})
      assert cluster.name == "prod"
    end

    test "name with hyphens passes" do
      assert {:ok, _} = apply(%{"name" => "my-cluster", "ipv4_range" => "100.64.1.0/24"})
    end

    test "24-character name is valid (max boundary)" do
      name = String.duplicate("a", 24)
      assert {:ok, cluster} = apply(%{"name" => name, "ipv4_range" => "100.64.1.0/24"})
      assert cluster.name == name
    end

    test "25-character name exceeds max length" do
      name = String.duplicate("a", 25)
      changeset = build_changeset(%{"name" => name, "ipv4_range" => "100.64.1.0/24"})
      assert %{name: [_msg]} = errors_on(changeset)
    end

    test "uppercase letters are rejected" do
      changeset = build_changeset(%{"name" => "Prod", "ipv4_range" => "100.64.1.0/24"})
      assert %{name: [_msg]} = errors_on(changeset)
    end

    test "leading hyphen is rejected" do
      changeset = build_changeset(%{"name" => "-prod", "ipv4_range" => "100.64.1.0/24"})
      assert %{name: [_msg]} = errors_on(changeset)
    end

    test "trailing hyphen is rejected" do
      changeset = build_changeset(%{"name" => "prod-", "ipv4_range" => "100.64.1.0/24"})
      assert %{name: [_msg]} = errors_on(changeset)
    end

    test "missing name generates a random name (maybe_generate_name)" do
      assert {:ok, cluster} = apply(%{"ipv4_range" => "100.64.1.0/24"})
      assert is_binary(cluster.name)
      assert String.length(cluster.name) > 0
    end

    test "generated name is 12 characters" do
      assert {:ok, cluster} = apply(%{"ipv4_range" => "100.64.1.0/24"})
      assert String.length(cluster.name) == 12
    end

    test "generated name is lowercase alphanumeric" do
      assert {:ok, cluster} = apply(%{"ipv4_range" => "100.64.1.0/24"})
      assert cluster.name =~ ~r/^[a-z0-9]+$/
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — ipv4_range CIDR format validation
  # ---------------------------------------------------------------------------

  describe "changeset/2 — ipv4_range CIDR format" do
    test "valid /24 CIDR passes" do
      assert {:ok, _} = apply(%{"name" => "prod", "ipv4_range" => "100.64.1.0/24"})
    end

    test "valid /10 CIDR passes" do
      assert {:ok, _} = apply(%{"name" => "prod", "ipv4_range" => "100.64.0.0/10"})
    end

    test "prefix /0 is valid format" do
      assert {:ok, _} = apply(%{"name" => "prod", "ipv4_range" => "100.64.1.0/0"})
    end

    test "prefix /32 is valid format" do
      assert {:ok, _} = apply(%{"name" => "prod", "ipv4_range" => "100.64.1.0/32"})
    end

    test "prefix > 32 is rejected" do
      changeset = build_changeset(%{"name" => "prod", "ipv4_range" => "100.64.1.0/33"})
      assert %{ipv4_range: [_msg]} = errors_on(changeset)
    end

    test "missing prefix slash is rejected" do
      changeset = build_changeset(%{"name" => "prod", "ipv4_range" => "100.64.1.0"})
      assert %{ipv4_range: [_msg]} = errors_on(changeset)
    end

    test "text string is rejected" do
      changeset = build_changeset(%{"name" => "prod", "ipv4_range" => "not-a-cidr"})
      assert %{ipv4_range: [_msg]} = errors_on(changeset)
    end

    test "octet > 255 is rejected by semantic validation" do
      changeset = build_changeset(%{"name" => "prod", "ipv4_range" => "300.64.1.0/24"})
      assert %{ipv4_range: [_msg]} = errors_on(changeset)
    end

    test "missing ipv4_range without name also fails on name required" do
      changeset = build_changeset(%{})
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :ipv4_range) or Map.has_key?(errors, :name)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — ipv4_range exclusion rules
  # ---------------------------------------------------------------------------

  describe "changeset/2 — ipv4_range exclusion rules" do
    # All blocked first octets: 0, 10, 127, 169, 172, 192, 224, 240, 255
    for {description, cidr} <- [
          {"0.x.x.x (reserved)", "0.0.0.0/24"},
          {"10.x.x.x (private)", "10.0.0.0/24"},
          {"127.x.x.x (loopback)", "127.0.0.1/24"},
          {"169.x.x.x (link-local)", "169.254.0.0/16"},
          {"172.x.x.x (private)", "172.16.0.0/12"},
          {"192.x.x.x (private)", "192.168.0.0/24"},
          {"224.x.x.x (multicast)", "224.0.0.0/4"},
          {"240.x.x.x (reserved)", "240.0.0.0/4"},
          {"255.x.x.x (broadcast)", "255.0.0.0/8"}
        ] do
      test "#{description} range is rejected" do
        changeset = build_changeset(%{"name" => "prod", "ipv4_range" => unquote(cidr)})
        assert %{ipv4_range: [msg]} = errors_on(changeset)
        assert msg =~ "private"
      end
    end

    test "100.64.x.x (CGNAT / allowed) passes exclusion check" do
      assert {:ok, _} = apply(%{"name" => "prod", "ipv4_range" => "100.64.0.0/24"})
    end

    test "198.x.x.x (allowed first octet) passes exclusion check" do
      assert {:ok, _} = apply(%{"name" => "prod", "ipv4_range" => "198.51.100.0/24"})
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — node_limit validation
  # ---------------------------------------------------------------------------

  describe "changeset/2 — node_limit field" do
    test "nil node_limit is allowed (no limit)" do
      assert {:ok, cluster} = apply(%{"name" => "prod", "ipv4_range" => "100.64.1.0/24", "node_limit" => nil})
      assert cluster.node_limit == nil
    end

    test "positive node_limit is accepted" do
      assert {:ok, cluster} = apply(%{"name" => "prod", "ipv4_range" => "100.64.1.0/24", "node_limit" => 5})
      assert cluster.node_limit == 5
    end

    test "node_limit of 1 is accepted (boundary)" do
      assert {:ok, cluster} = apply(%{"name" => "prod", "ipv4_range" => "100.64.1.0/24", "node_limit" => 1})
      assert cluster.node_limit == 1
    end

    test "node_limit of 0 is rejected" do
      changeset = build_changeset(%{"name" => "prod", "ipv4_range" => "100.64.1.0/24", "node_limit" => 0})
      assert %{node_limit: [_msg]} = errors_on(changeset)
    end

    test "negative node_limit is rejected" do
      changeset = build_changeset(%{"name" => "prod", "ipv4_range" => "100.64.1.0/24", "node_limit" => -1})
      assert %{node_limit: [_msg]} = errors_on(changeset)
    end

    test "omitted node_limit defaults to nil" do
      assert {:ok, cluster} = apply(%{"name" => "prod", "ipv4_range" => "100.64.1.0/24"})
      assert cluster.node_limit == nil
    end
  end

  # ---------------------------------------------------------------------------
  # network_name/1
  # ---------------------------------------------------------------------------

  describe "network_name/1" do
    test "returns cluster-{name} format" do
      cluster = %Cluster{name: "prod"}
      assert Cluster.network_name(cluster) == "cluster-prod"
    end

    test "hyphenated cluster name is preserved" do
      cluster = %Cluster{name: "prod-east"}
      assert Cluster.network_name(cluster) == "cluster-prod-east"
    end
  end

  # ---------------------------------------------------------------------------
  # vpn_domain/1
  # ---------------------------------------------------------------------------

  describe "vpn_domain/1" do
    test "returns cluster-{name}.nm.internal by default" do
      # test.exs sets netmaker_default_domain to "nm.internal"
      cluster = %Cluster{name: "prod"}
      assert Cluster.vpn_domain(cluster) == "cluster-prod.nm.internal"
    end

    test "hyphenated cluster name is preserved in domain" do
      cluster = %Cluster{name: "prod-east"}
      assert Cluster.vpn_domain(cluster) == "cluster-prod-east.nm.internal"
    end

    test "vpn_domain is distinct from network_name (has domain suffix)" do
      cluster = %Cluster{name: "prod"}
      assert Cluster.vpn_domain(cluster) != Cluster.network_name(cluster)
      assert String.starts_with?(Cluster.vpn_domain(cluster), Cluster.network_name(cluster))
    end
  end

  # ---------------------------------------------------------------------------
  # node_count/1
  # ---------------------------------------------------------------------------

  describe "node_count/1" do
    test "returns length of loaded nodes list" do
      cluster = %Cluster{nodes: [%{id: "a"}, %{id: "b"}, %{id: "c"}]}
      assert Cluster.node_count(cluster) == 3
    end

    test "returns 0 for empty nodes list" do
      cluster = %Cluster{nodes: []}
      assert Cluster.node_count(cluster) == 0
    end

    test "returns 0 when nodes association is not loaded" do
      cluster = %Cluster{nodes: %NotLoaded{}}
      assert Cluster.node_count(cluster) == 0
    end

    test "returns 1 for single-node list" do
      cluster = %Cluster{nodes: [%{id: "only"}]}
      assert Cluster.node_count(cluster) == 1
    end
  end
end
