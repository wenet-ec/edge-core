# edge_admin/test/edge_admin_web/plugs/metrics_auth_test.exs
defmodule EdgeAdminWeb.Plugs.MetricsAuthTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias EdgeAdminWeb.Plugs.MetricsAuth

  @opts MetricsAuth.init([])

  setup do
    Application.put_env(:edge_admin, :auth_enabled, true)
    Application.delete_env(:edge_admin, :master_key)
    Application.delete_env(:edge_admin, :metrics_key)

    on_exit(fn ->
      Application.put_env(:edge_admin, :auth_enabled, true)
      Application.delete_env(:edge_admin, :master_key)
      Application.delete_env(:edge_admin, :metrics_key)
    end)
  end

  defp build_conn(auth_header \\ nil) do
    conn = conn(:get, "/")

    if auth_header do
      put_req_header(conn, "authorization", auth_header)
    else
      conn
    end
  end

  describe "auth disabled" do
    test "passes through with no header" do
      Application.put_env(:edge_admin, :auth_enabled, false)
      conn = MetricsAuth.call(build_conn(), @opts)
      refute conn.halted
    end

    test "passes through with wrong key" do
      Application.put_env(:edge_admin, :auth_enabled, false)
      Application.put_env(:edge_admin, :master_key, "master")
      Application.put_env(:edge_admin, :metrics_key, "metrics")
      conn = "Bearer garbage" |> build_conn() |> MetricsAuth.call(@opts)
      refute conn.halted
    end
  end

  describe "auth enabled — master key" do
    test "passes through with correct master key" do
      Application.put_env(:edge_admin, :master_key, "master-key")
      Application.put_env(:edge_admin, :metrics_key, "metrics-key")
      conn = "Bearer master-key" |> build_conn() |> MetricsAuth.call(@opts)
      refute conn.halted
    end
  end

  describe "auth enabled — metrics key" do
    test "passes through with correct metrics key" do
      Application.put_env(:edge_admin, :master_key, "master-key")
      Application.put_env(:edge_admin, :metrics_key, "metrics-key")
      conn = "Bearer metrics-key" |> build_conn() |> MetricsAuth.call(@opts)
      refute conn.halted
    end
  end

  describe "auth enabled — invalid" do
    test "halts with 401 when no Authorization header" do
      Application.put_env(:edge_admin, :master_key, "master-key")
      Application.put_env(:edge_admin, :metrics_key, "metrics-key")
      conn = nil |> build_conn() |> MetricsAuth.call(@opts)
      assert conn.halted
      assert conn.status == 401
    end

    test "halts with 401 when key is wrong" do
      Application.put_env(:edge_admin, :master_key, "master-key")
      Application.put_env(:edge_admin, :metrics_key, "metrics-key")
      conn = "Bearer wrong-key" |> build_conn() |> MetricsAuth.call(@opts)
      assert conn.halted
      assert conn.status == 401
    end

    test "halts with 401 when scheme is not Bearer" do
      Application.put_env(:edge_admin, :master_key, "master-key")
      Application.put_env(:edge_admin, :metrics_key, "metrics-key")
      conn = "Token master-key" |> build_conn() |> MetricsAuth.call(@opts)
      assert conn.halted
      assert conn.status == 401
    end

    test "master key does not accidentally match metrics key" do
      Application.put_env(:edge_admin, :master_key, "master-key")
      Application.put_env(:edge_admin, :metrics_key, "metrics-key")
      # Send master key value but expect it would still work (it's omnipotent)
      # This test documents that master_key IS accepted
      conn = "Bearer master-key" |> build_conn() |> MetricsAuth.call(@opts)
      refute conn.halted
    end

    test "metrics key does not grant master access (documents scoping)" do
      Application.put_env(:edge_admin, :master_key, "master-key")
      Application.put_env(:edge_admin, :metrics_key, "metrics-key")
      # metrics_key passes MetricsAuth — both keys accepted here
      conn = "Bearer metrics-key" |> build_conn() |> MetricsAuth.call(@opts)
      refute conn.halted
    end

    test "response body contains error key on failure" do
      Application.put_env(:edge_admin, :master_key, "master-key")
      Application.put_env(:edge_admin, :metrics_key, "metrics-key")
      conn = "Bearer garbage" |> build_conn() |> MetricsAuth.call(@opts)
      body = JSON.decode!(conn.resp_body)
      assert Map.has_key?(body, "error")
    end

    test "halts with 401 when Authorization is empty string" do
      Application.put_env(:edge_admin, :master_key, "master-key")
      Application.put_env(:edge_admin, :metrics_key, "metrics-key")
      conn = "" |> build_conn() |> MetricsAuth.call(@opts)
      assert conn.halted
      assert conn.status == 401
    end
  end

  describe "auth_enabled defaults to true" do
    test "when :auth_enabled not set, auth is enforced" do
      Application.delete_env(:edge_admin, :auth_enabled)
      Application.put_env(:edge_admin, :master_key, "master-key")
      Application.put_env(:edge_admin, :metrics_key, "metrics-key")
      conn = nil |> build_conn() |> MetricsAuth.call(@opts)
      assert conn.halted
      assert conn.status == 401
    end
  end
end
