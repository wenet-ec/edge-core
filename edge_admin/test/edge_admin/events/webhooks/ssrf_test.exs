# edge_admin/test/edge_admin/events/webhooks/ssrf_test.exs
defmodule EdgeAdmin.Events.Webhooks.SsrfTest do
  use ExUnit.Case, async: false

  alias EdgeAdmin.Events.Webhooks.Ssrf

  setup do
    # Tests run against the production setting (SSRF on) regardless of the
    # surrounding test environment, then restore the original on exit.
    original = Elixir.Application.get_env(:edge_admin, :webhook_allow_private_ips, false)
    Elixir.Application.put_env(:edge_admin, :webhook_allow_private_ips, false)

    on_exit(fn ->
      Elixir.Application.put_env(:edge_admin, :webhook_allow_private_ips, original)
    end)

    :ok
  end

  describe "validate_url/1 — URL hygiene" do
    test "accepts a plain https URL with a public-looking host literal" do
      assert :ok = Ssrf.validate_url("https://203.0.113.10/hook")
    end

    test "rejects non-http(s) schemes" do
      assert {:error, :invalid_url} = Ssrf.validate_url("ftp://example.com/")
      assert {:error, :invalid_url} = Ssrf.validate_url("file:///etc/passwd")
    end

    test "rejects userinfo" do
      assert {:error, :userinfo_not_allowed} = Ssrf.validate_url("https://user:pass@203.0.113.10/")
    end

    test "rejects fragments" do
      assert {:error, :fragment_not_allowed} = Ssrf.validate_url("https://203.0.113.10/#frag")
    end

    test "rejects malformed input" do
      assert {:error, :invalid_url} = Ssrf.validate_url("not a url")
      assert {:error, :invalid_url} = Ssrf.validate_url("https://")
    end
  end

  describe "validate_url/1 — IP literal deny list" do
    test "blocks loopback v4" do
      assert {:error, {:denied, _, _}} = Ssrf.validate_url("https://127.0.0.1/")
    end

    test "blocks RFC1918 ranges" do
      assert {:error, {:denied, _, _}} = Ssrf.validate_url("https://10.0.0.1/")
      assert {:error, {:denied, _, _}} = Ssrf.validate_url("https://172.16.0.1/")
      assert {:error, {:denied, _, _}} = Ssrf.validate_url("https://192.168.1.1/")
    end

    test "blocks link-local (cloud metadata range)" do
      assert {:error, {:denied, _, _}} = Ssrf.validate_url("https://169.254.169.254/")
    end

    test "blocks Aliyun metadata literal" do
      assert {:error, {:denied, _, _}} = Ssrf.validate_url("https://100.100.100.200/")
    end

    test "blocks loopback v6" do
      assert {:error, {:denied, _, _}} = Ssrf.validate_url("https://[::1]/")
    end

    test "IPv4-mapped v6 normalizes — 127.0.0.1 in v6 form is still blocked" do
      assert {:error, {:denied, _, _}} = Ssrf.validate_url("https://[::ffff:127.0.0.1]/")
    end
  end

  describe "validate_url/1 — host deny list" do
    test "blocks well-known cloud metadata hostnames" do
      assert {:error, {:denied_host, _}} = Ssrf.validate_url("https://metadata.google.internal/")
      assert {:error, {:denied_host, _}} = Ssrf.validate_url("https://metadata.azure.internal/")
      assert {:error, {:denied_host, _}} = Ssrf.validate_url("https://metadata.tencentyun.com/")
    end

    test "case-insensitive and trailing-dot tolerant" do
      assert {:error, {:denied_host, _}} = Ssrf.validate_url("https://Metadata.Google.Internal/")
      assert {:error, {:denied_host, _}} = Ssrf.validate_url("https://metadata.google.internal./")
    end
  end

  describe "validate_url/1 — opt-out" do
    test "WEBHOOK_ALLOW_PRIVATE_IPS=true skips the deny list" do
      Elixir.Application.put_env(:edge_admin, :webhook_allow_private_ips, true)
      assert :ok = Ssrf.validate_url("https://127.0.0.1/")
      assert :ok = Ssrf.validate_url("https://10.0.0.1/")
    end
  end
end
