defmodule EdgeAdmin.ProxyServers.AuthenticationTest do
  use ExUnit.Case, async: true

  import Mox

  alias EdgeAdmin.ProxyServers.Authentication

  # Mox requires that mocks are verified after each test
  setup :verify_on_exit!

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Stub a node struct with just what Authentication returns
  defp stub_node(id \\ "abc-123") do
    %{id: id}
  end

  defp with_auth_disabled(fun) do
    Application.put_env(:edge_admin, :auth_enabled, false)
    fun.()
  after
    Application.delete_env(:edge_admin, :auth_enabled)
  end

  defp with_proxy_key(key, fun) do
    Application.put_env(:edge_admin, :auth_enabled, true)
    Application.put_env(:edge_admin, :proxy_key, key)
    fun.()
  after
    Application.delete_env(:edge_admin, :auth_enabled)
    Application.delete_env(:edge_admin, :proxy_key)
  end

  # ---------------------------------------------------------------------------
  # Password authentication
  # ---------------------------------------------------------------------------

  describe "authenticate_and_parse/2 - password" do
    test "wrong password returns invalid_credentials" do
      with_proxy_key("correct-key", fn ->
        assert {:error, :invalid_credentials} =
                 Authentication.authenticate_and_parse("_", "wrong-key")
      end)
    end

    test "correct password passes through" do
      with_proxy_key("correct-key", fn ->
        # "_" username → direct mode, no DB call needed
        assert {:ok, :direct} = Authentication.authenticate_and_parse("_", "correct-key")
      end)
    end

    test "auth disabled bypasses password check" do
      with_auth_disabled(fn ->
        assert {:ok, :direct} = Authentication.authenticate_and_parse("_", "garbage")
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Direct routing mode (username "_" or "")
  # ---------------------------------------------------------------------------

  describe "authenticate_and_parse/2 - direct routing" do
    setup do
      Application.put_env(:edge_admin, :auth_enabled, false)
      on_exit(fn -> Application.delete_env(:edge_admin, :auth_enabled) end)
    end

    test "underscore username routes direct" do
      assert {:ok, :direct} = Authentication.authenticate_and_parse("_", "any")
    end

    test "empty username routes direct" do
      assert {:ok, :direct} = Authentication.authenticate_and_parse("", "any")
    end
  end

  # ---------------------------------------------------------------------------
  # DNS parsing - format validation
  # ---------------------------------------------------------------------------

  describe "authenticate_and_parse/2 - DNS format" do
    setup do
      Application.put_env(:edge_admin, :auth_enabled, false)
      Application.put_env(:edge_admin, :netmaker_default_domain, "nm.internal")

      on_exit(fn ->
        Application.delete_env(:edge_admin, :auth_enabled)
        Application.delete_env(:edge_admin, :netmaker_default_domain)
      end)
    end

    test "invalid DNS format returns error without hitting DB" do
      # No Mox expectation set - any DB call would crash the test
      assert {:error, :invalid_dns_format} =
               Authentication.authenticate_and_parse("not-a-valid-hostname", "any")
    end

    test "bare hostname with no dots is invalid" do
      assert {:error, :invalid_dns_format} =
               Authentication.authenticate_and_parse("nodename", "any")
    end

    test "wrong prefix (host- instead of node-) is invalid" do
      assert {:error, :invalid_dns_format} =
               Authentication.authenticate_and_parse(
                 "host-abc123.cluster-default.nm.internal",
                 "any"
               )
    end

    test "cluster segment missing cluster- prefix is invalid" do
      assert {:error, :invalid_dns_format} =
               Authentication.authenticate_and_parse(
                 "node-abc123.default.nm.internal",
                 "any"
               )
    end

    test "wrong domain suffix is invalid" do
      assert {:error, :invalid_dns_format} =
               Authentication.authenticate_and_parse(
                 "node-abc123.cluster-default.wrong.domain",
                 "any"
               )
    end

    test "valid DNS format hits DB lookup" do
      # identifier captured by regex is "abc123" (after stripping "node-" prefix)
      stub(EdgeAdmin.NodesMock, :list_node_identifiers_by_cluster, fn "default" ->
        {:ok, %{"abc123" => stub_node()}}
      end)

      assert {:ok, :chain, _node} =
               Authentication.authenticate_and_parse(
                 "node-abc123.cluster-default.nm.internal",
                 "any"
               )
    end

    test "custom domain in config is respected" do
      Application.put_env(:edge_admin, :netmaker_default_domain, "custom.vpn")

      # DNS: node-xyz.cluster-prod.custom.vpn → identifier "xyz"
      stub(EdgeAdmin.NodesMock, :list_node_identifiers_by_cluster, fn "prod" ->
        {:ok, %{"xyz" => stub_node("xyz")}}
      end)

      assert {:ok, :chain, _node} =
               Authentication.authenticate_and_parse(
                 "node-xyz.cluster-prod.custom.vpn",
                 "any"
               )

      Application.put_env(:edge_admin, :netmaker_default_domain, "nm.internal")
    end
  end

  # ---------------------------------------------------------------------------
  # Node/cluster lookup
  # ---------------------------------------------------------------------------

  describe "authenticate_and_parse/2 - node lookup" do
    setup do
      Application.put_env(:edge_admin, :auth_enabled, false)
      Application.put_env(:edge_admin, :netmaker_default_domain, "nm.internal")

      on_exit(fn ->
        Application.delete_env(:edge_admin, :auth_enabled)
        Application.delete_env(:edge_admin, :netmaker_default_domain)
      end)
    end

    test "known node ID resolves to chain mode" do
      node = stub_node("abc123")

      # DNS: node-abc123.cluster-default.nm.internal
      # regex captures identifier "abc123" (everything after "node-" up to next dot)
      expect(EdgeAdmin.NodesMock, :list_node_identifiers_by_cluster, fn "default" ->
        {:ok, %{"abc123" => node}}
      end)

      assert {:ok, :chain, ^node} =
               Authentication.authenticate_and_parse(
                 "node-abc123.cluster-default.nm.internal",
                 "any"
               )
    end

    test "alias resolves to the node it points to" do
      node = stub_node("abc123")

      # DNS: node-web.cluster-default.nm.internal → identifier "web"
      expect(EdgeAdmin.NodesMock, :list_node_identifiers_by_cluster, fn "default" ->
        {:ok, %{"abc123" => node, "web" => node}}
      end)

      assert {:ok, :chain, ^node} =
               Authentication.authenticate_and_parse(
                 "node-web.cluster-default.nm.internal",
                 "any"
               )
    end

    test "unknown identifier returns node_not_found" do
      expect(EdgeAdmin.NodesMock, :list_node_identifiers_by_cluster, fn "default" ->
        {:ok, %{"other" => stub_node("other")}}
      end)

      assert {:error, :node_not_found} =
               Authentication.authenticate_and_parse(
                 "node-unknown.cluster-default.nm.internal",
                 "any"
               )
    end

    test "cluster not found returns cluster_not_found" do
      expect(EdgeAdmin.NodesMock, :list_node_identifiers_by_cluster, fn "nonexistent" ->
        {:error, :not_found}
      end)

      assert {:error, :cluster_not_found} =
               Authentication.authenticate_and_parse(
                 "node-abc123.cluster-nonexistent.nm.internal",
                 "any"
               )
    end

    test "cluster name is extracted without cluster- prefix before DB call" do
      # DNS: node-n1.cluster-prod.nm.internal → cluster_name passed to DB is "prod", not "cluster-prod"
      expect(EdgeAdmin.NodesMock, :list_node_identifiers_by_cluster, fn cluster_name ->
        assert cluster_name == "prod"
        {:ok, %{"n1" => stub_node("n1")}}
      end)

      Authentication.authenticate_and_parse(
        "node-n1.cluster-prod.nm.internal",
        "any"
      )
    end
  end
end
