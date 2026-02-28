# edge_agent/test/edge_agent/proxy_servers/destination_validator_test.exs
defmodule EdgeAgent.ProxyServers.DestinationValidatorTest do
  use ExUnit.Case, async: false

  alias EdgeAgent.ProxyServers.DestinationValidator

  # Helpers to temporarily set Application env then restore
  defp with_app_env(key, value, fun) do
    old = Application.get_env(:edge_agent, key)
    Application.put_env(:edge_agent, key, value)

    try do
      fun.()
    after
      if old == nil do
        Application.delete_env(:edge_agent, key)
      else
        Application.put_env(:edge_agent, key, old)
      end
    end
  end

  # -----------------------------------------------------------------------
  # localhost?/1
  # -----------------------------------------------------------------------

  describe "localhost?/1" do
    test "\"localhost\" is loopback" do
      assert DestinationValidator.localhost?("localhost")
    end

    test "\"LOCALHOST\" is loopback (case-insensitive)" do
      assert DestinationValidator.localhost?("LOCALHOST")
    end

    test "\"127.0.0.1\" is loopback" do
      assert DestinationValidator.localhost?("127.0.0.1")
    end

    test "\"0.0.0.0\" is loopback" do
      assert DestinationValidator.localhost?("0.0.0.0")
    end

    test "\"::1\" is loopback" do
      assert DestinationValidator.localhost?("::1")
    end

    test "\"::ffff:127.0.0.1\" is loopback" do
      assert DestinationValidator.localhost?("::ffff:127.0.0.1")
    end

    test "any 127.x.x.x address is loopback" do
      assert DestinationValidator.localhost?("127.255.255.255")
      assert DestinationValidator.localhost?("127.0.0.2")
      assert DestinationValidator.localhost?("127.1.2.3")
    end

    test "IPv6 loopback variation with ::1 in string" do
      assert DestinationValidator.localhost?("::1")
    end

    test "public IP is not loopback" do
      refute DestinationValidator.localhost?("8.8.8.8")
    end

    test "private LAN IP is not loopback" do
      refute DestinationValidator.localhost?("192.168.1.1")
      refute DestinationValidator.localhost?("10.0.0.1")
    end

    test "hostname that is not localhost is not loopback" do
      refute DestinationValidator.localhost?("example.com")
    end

    test "169.254.x.x is not loopback (link-local, different check)" do
      refute DestinationValidator.localhost?("169.254.1.1")
    end
  end

  # -----------------------------------------------------------------------
  # metadata_service?/1
  # -----------------------------------------------------------------------

  describe "metadata_service?/1" do
    test "169.254.169.254 is a metadata service" do
      assert DestinationValidator.metadata_service?("169.254.169.254")
    end

    test "100.100.100.200 is a metadata service (Alibaba)" do
      assert DestinationValidator.metadata_service?("100.100.100.200")
    end

    test "metadata.google.internal is a metadata service" do
      assert DestinationValidator.metadata_service?("metadata.google.internal")
    end

    test "metadata.azure.com is a metadata service" do
      assert DestinationValidator.metadata_service?("metadata.azure.com")
    end

    test "case-insensitive matching" do
      assert DestinationValidator.metadata_service?("METADATA.GOOGLE.INTERNAL")
      assert DestinationValidator.metadata_service?("Metadata.Azure.Com")
    end

    test "public IP is not a metadata service" do
      refute DestinationValidator.metadata_service?("8.8.8.8")
    end

    test "similar-looking hostname is not a metadata service" do
      refute DestinationValidator.metadata_service?("my-metadata.google.internal")
      refute DestinationValidator.metadata_service?("notmetadata.azure.com")
    end

    test "169.254.1.1 is not a metadata service (only .254 is blocked)" do
      refute DestinationValidator.metadata_service?("169.254.1.1")
    end
  end

  # -----------------------------------------------------------------------
  # link_local?/1
  # -----------------------------------------------------------------------

  describe "link_local?/1" do
    test "169.254.0.0 is link-local" do
      assert DestinationValidator.link_local?("169.254.0.0")
    end

    test "169.254.1.1 is link-local" do
      assert DestinationValidator.link_local?("169.254.1.1")
    end

    test "169.254.255.255 is link-local" do
      assert DestinationValidator.link_local?("169.254.255.255")
    end

    test "169.253.x.x is not link-local" do
      refute DestinationValidator.link_local?("169.253.1.1")
    end

    test "public IP is not link-local" do
      refute DestinationValidator.link_local?("8.8.8.8")
    end

    test "hostname is not link-local" do
      refute DestinationValidator.link_local?("example.com")
    end

    test "127.0.0.1 is not link-local" do
      refute DestinationValidator.link_local?("127.0.0.1")
    end
  end

  # -----------------------------------------------------------------------
  # docker_port?/1
  # -----------------------------------------------------------------------

  describe "docker_port?/1" do
    test "2375 is Docker API port" do
      assert DestinationValidator.docker_port?(2375)
    end

    test "2376 is Docker TLS API port" do
      assert DestinationValidator.docker_port?(2376)
    end

    test "2377 is Docker Swarm port" do
      assert DestinationValidator.docker_port?(2377)
    end

    test "80 is not a Docker port" do
      refute DestinationValidator.docker_port?(80)
    end

    test "443 is not a Docker port" do
      refute DestinationValidator.docker_port?(443)
    end

    test "2374 is not a Docker port (adjacent)" do
      refute DestinationValidator.docker_port?(2374)
    end
  end

  # -----------------------------------------------------------------------
  # kubernetes_port?/1
  # -----------------------------------------------------------------------

  describe "kubernetes_port?/1" do
    test "6443 is K8s API server port" do
      assert DestinationValidator.kubernetes_port?(6443)
    end

    test "10250 is Kubelet API port" do
      assert DestinationValidator.kubernetes_port?(10_250)
    end

    test "10255 is Kubelet read-only port" do
      assert DestinationValidator.kubernetes_port?(10_255)
    end

    test "2379 is etcd client port" do
      assert DestinationValidator.kubernetes_port?(2379)
    end

    test "2380 is etcd peer port" do
      assert DestinationValidator.kubernetes_port?(2380)
    end

    test "80 is not a K8s port" do
      refute DestinationValidator.kubernetes_port?(80)
    end

    test "6444 is not a K8s port (adjacent)" do
      refute DestinationValidator.kubernetes_port?(6444)
    end
  end

  # -----------------------------------------------------------------------
  # metrics_port?/1
  # -----------------------------------------------------------------------

  describe "metrics_port?/1" do
    test "host_metrics_port is blocked" do
      with_app_env(:host_metrics_port, 49_100, fn ->
        with_app_env(:wireguard_metrics_port, 49_586, fn ->
          assert DestinationValidator.metrics_port?(49_100)
        end)
      end)
    end

    test "wireguard_metrics_port is blocked" do
      with_app_env(:host_metrics_port, 49_100, fn ->
        with_app_env(:wireguard_metrics_port, 49_586, fn ->
          assert DestinationValidator.metrics_port?(49_586)
        end)
      end)
    end

    test "other port is not a metrics port" do
      with_app_env(:host_metrics_port, 49_100, fn ->
        with_app_env(:wireguard_metrics_port, 49_586, fn ->
          refute DestinationValidator.metrics_port?(80)
          refute DestinationValidator.metrics_port?(443)
          refute DestinationValidator.metrics_port?(9100)
        end)
      end)
    end
  end

  # -----------------------------------------------------------------------
  # custom_blocked?/2
  # -----------------------------------------------------------------------

  describe "custom_blocked?/2" do
    test "host-only entry blocks all ports for that host" do
      with_app_env(:proxy_custom_blocked_hosts, ["evil.com"], fn ->
        with_app_env(:proxy_blocked_ports, [], fn ->
          assert DestinationValidator.custom_blocked?("evil.com", 80)
          assert DestinationValidator.custom_blocked?("evil.com", 443)
          assert DestinationValidator.custom_blocked?("evil.com", 9999)
        end)
      end)
    end

    test "host-only entry is case-insensitive" do
      with_app_env(:proxy_custom_blocked_hosts, ["Evil.Com"], fn ->
        with_app_env(:proxy_blocked_ports, [], fn ->
          assert DestinationValidator.custom_blocked?("evil.com", 80)
          assert DestinationValidator.custom_blocked?("EVIL.COM", 80)
        end)
      end)
    end

    test "host+port entry blocks only that specific port" do
      with_app_env(:proxy_custom_blocked_hosts, [{"internal-db.local", 5432}], fn ->
        with_app_env(:proxy_blocked_ports, [], fn ->
          assert DestinationValidator.custom_blocked?("internal-db.local", 5432)
          refute DestinationValidator.custom_blocked?("internal-db.local", 80)
        end)
      end)
    end

    test "port-only block (proxy_blocked_ports) blocks that port on any host" do
      with_app_env(:proxy_custom_blocked_hosts, [], fn ->
        with_app_env(:proxy_blocked_ports, [44_000, 44_880], fn ->
          assert DestinationValidator.custom_blocked?("some-host.com", 44_000)
          assert DestinationValidator.custom_blocked?("another-host.com", 44_880)
          refute DestinationValidator.custom_blocked?("some-host.com", 80)
        end)
      end)
    end

    test "nothing blocked when lists are empty" do
      with_app_env(:proxy_custom_blocked_hosts, [], fn ->
        with_app_env(:proxy_blocked_ports, [], fn ->
          refute DestinationValidator.custom_blocked?("anything.com", 80)
        end)
      end)
    end

    test "non-listed host is not blocked" do
      with_app_env(:proxy_custom_blocked_hosts, ["evil.com"], fn ->
        with_app_env(:proxy_blocked_ports, [], fn ->
          refute DestinationValidator.custom_blocked?("good.com", 80)
        end)
      end)
    end
  end

  # -----------------------------------------------------------------------
  # custom_allowed?/2
  # -----------------------------------------------------------------------

  describe "custom_allowed?/2" do
    test "host-only entry allows all ports for that host" do
      with_app_env(:proxy_custom_allowed_hosts, ["trusted.internal"], fn ->
        assert DestinationValidator.custom_allowed?("trusted.internal", 80)
        assert DestinationValidator.custom_allowed?("trusted.internal", 5432)
      end)
    end

    test "host-only entry is case-insensitive" do
      with_app_env(:proxy_custom_allowed_hosts, ["Trusted.Internal"], fn ->
        assert DestinationValidator.custom_allowed?("trusted.internal", 80)
        assert DestinationValidator.custom_allowed?("TRUSTED.INTERNAL", 80)
      end)
    end

    test "host+port entry allows only that specific port" do
      with_app_env(:proxy_custom_allowed_hosts, [{"special.internal", 8080}], fn ->
        assert DestinationValidator.custom_allowed?("special.internal", 8080)
        refute DestinationValidator.custom_allowed?("special.internal", 443)
      end)
    end

    test "empty allowlist allows nothing" do
      with_app_env(:proxy_custom_allowed_hosts, [], fn ->
        refute DestinationValidator.custom_allowed?("anything.com", 80)
      end)
    end

    test "non-listed host is not allowed" do
      with_app_env(:proxy_custom_allowed_hosts, ["trusted.internal"], fn ->
        refute DestinationValidator.custom_allowed?("other.internal", 80)
      end)
    end
  end

  # -----------------------------------------------------------------------
  # validate_destination/2 — integration of all checks
  # -----------------------------------------------------------------------

  describe "validate_destination/2" do
    setup do
      # Baseline: no custom lists, sensible metrics ports
      Application.put_env(:edge_agent, :proxy_custom_allowed_hosts, [])
      Application.put_env(:edge_agent, :proxy_custom_blocked_hosts, [])
      Application.put_env(:edge_agent, :proxy_blocked_ports, [])
      Application.put_env(:edge_agent, :host_metrics_port, 49_100)
      Application.put_env(:edge_agent, :wireguard_metrics_port, 49_586)

      on_exit(fn ->
        Application.delete_env(:edge_agent, :proxy_custom_allowed_hosts)
        Application.delete_env(:edge_agent, :proxy_custom_blocked_hosts)
        Application.delete_env(:edge_agent, :proxy_blocked_ports)
        Application.delete_env(:edge_agent, :host_metrics_port)
        Application.delete_env(:edge_agent, :wireguard_metrics_port)
      end)
    end

    test "public internet is allowed" do
      assert :ok = DestinationValidator.validate_destination("8.8.8.8", 443)
      assert :ok = DestinationValidator.validate_destination("example.com", 80)
    end

    test "private LAN addresses are allowed (not SSRF risk)" do
      assert :ok = DestinationValidator.validate_destination("192.168.1.1", 80)
      assert :ok = DestinationValidator.validate_destination("10.0.0.1", 8080)
      assert :ok = DestinationValidator.validate_destination("172.16.0.1", 443)
    end

    test "localhost is blocked" do
      assert {:error, :localhost_blocked} = DestinationValidator.validate_destination("localhost", 80)
      assert {:error, :localhost_blocked} = DestinationValidator.validate_destination("127.0.0.1", 80)
    end

    test "cloud metadata IP 169.254.169.254 is blocked as metadata_service" do
      # metadata_service? is checked before link_local? in cond, so reason is :metadata_service_blocked
      assert {:error, :metadata_service_blocked} =
               DestinationValidator.validate_destination("169.254.169.254", 80)
    end

    test "link-local address (not metadata) is blocked" do
      assert {:error, :link_local_blocked} =
               DestinationValidator.validate_destination("169.254.1.1", 80)
    end

    test "Docker API ports are blocked" do
      assert {:error, :docker_port_blocked} =
               DestinationValidator.validate_destination("example.com", 2375)

      assert {:error, :docker_port_blocked} =
               DestinationValidator.validate_destination("192.168.1.1", 2376)
    end

    test "Kubernetes API ports are blocked" do
      assert {:error, :kubernetes_port_blocked} =
               DestinationValidator.validate_destination("example.com", 6443)

      assert {:error, :kubernetes_port_blocked} =
               DestinationValidator.validate_destination("example.com", 10_250)
    end

    test "metrics ports are blocked" do
      assert {:error, :metrics_port_blocked} =
               DestinationValidator.validate_destination("example.com", 49_100)

      assert {:error, :metrics_port_blocked} =
               DestinationValidator.validate_destination("example.com", 49_586)
    end

    test "custom blocked host is blocked" do
      Application.put_env(:edge_agent, :proxy_custom_blocked_hosts, ["internal-api.local"])

      assert {:error, :custom_blocked} =
               DestinationValidator.validate_destination("internal-api.local", 80)
    end

    test "custom blocked port is blocked" do
      Application.put_env(:edge_agent, :proxy_blocked_ports, [44_000])

      assert {:error, :custom_blocked} =
               DestinationValidator.validate_destination("example.com", 44_000)
    end

    test "custom allowlist overrides localhost block (highest priority)" do
      Application.put_env(:edge_agent, :proxy_custom_allowed_hosts, ["localhost"])

      # Normally localhost is blocked, allowlist overrides it
      assert :ok = DestinationValidator.validate_destination("localhost", 8080)
    end

    test "custom allowlist overrides docker port block" do
      Application.put_env(:edge_agent, :proxy_custom_allowed_hosts, [{"trusted-docker.local", 2375}])

      assert :ok = DestinationValidator.validate_destination("trusted-docker.local", 2375)
    end

    test "custom allowlist host+port does not override a different port" do
      Application.put_env(:edge_agent, :proxy_custom_allowed_hosts, [{"trusted-docker.local", 2375}])

      # Port 2376 is still blocked even though the host is in allowlist (different port)
      assert {:error, :docker_port_blocked} =
               DestinationValidator.validate_destination("trusted-docker.local", 2376)
    end
  end

  # -----------------------------------------------------------------------
  # error_message/1
  # -----------------------------------------------------------------------

  describe "error_message/1" do
    test "all known reasons return non-empty string" do
      reasons = [
        :localhost_blocked,
        :metadata_service_blocked,
        :link_local_blocked,
        :docker_port_blocked,
        :kubernetes_port_blocked,
        :metrics_port_blocked,
        :custom_blocked
      ]

      for reason <- reasons do
        msg = DestinationValidator.error_message(reason)
        assert is_binary(msg) and byte_size(msg) > 0, "empty message for #{reason}"
      end
    end

    test "each reason has a distinct message" do
      reasons = [
        :localhost_blocked,
        :metadata_service_blocked,
        :link_local_blocked,
        :docker_port_blocked,
        :kubernetes_port_blocked,
        :metrics_port_blocked,
        :custom_blocked
      ]

      messages = Enum.map(reasons, &DestinationValidator.error_message/1)
      assert length(Enum.uniq(messages)) == length(messages)
    end

    test "unknown reason returns generic fallback" do
      msg = DestinationValidator.error_message(:some_unknown_reason)
      assert is_binary(msg) and byte_size(msg) > 0
    end

    test "localhost_blocked message mentions security" do
      msg = DestinationValidator.error_message(:localhost_blocked)
      assert msg =~ "security"
    end

    test "docker_port_blocked message mentions Docker" do
      msg = DestinationValidator.error_message(:docker_port_blocked)
      assert msg =~ "Docker"
    end

    test "kubernetes_port_blocked message mentions Kubernetes" do
      msg = DestinationValidator.error_message(:kubernetes_port_blocked)
      assert msg =~ "Kubernetes"
    end
  end
end
