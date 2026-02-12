defmodule EdgeAdminWeb.Plugs.MasterKeyAuthTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias EdgeAdminWeb.Plugs.MasterKeyAuth

  @opts MasterKeyAuth.init([])

  setup do
    on_exit(fn ->
      Application.put_env(:edge_admin, :auth_enabled, true)
      Application.delete_env(:edge_admin, :master_key)
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
    test "passes through regardless of header" do
      Application.put_env(:edge_admin, :auth_enabled, false)
      conn = MasterKeyAuth.call(build_conn(), @opts)
      refute conn.halted
    end

    test "passes through even with wrong key" do
      Application.put_env(:edge_admin, :auth_enabled, false)
      Application.put_env(:edge_admin, :master_key, "real-key")
      conn = "Bearer wrong-key" |> build_conn() |> MasterKeyAuth.call(@opts)
      refute conn.halted
    end

    test "passes through with no header" do
      Application.put_env(:edge_admin, :auth_enabled, false)
      conn = nil |> build_conn() |> MasterKeyAuth.call(@opts)
      refute conn.halted
    end
  end

  describe "auth enabled — valid key" do
    test "passes through with correct Bearer key" do
      Application.put_env(:edge_admin, :master_key, "secret-master-key")
      conn = "Bearer secret-master-key" |> build_conn() |> MasterKeyAuth.call(@opts)
      refute conn.halted
      assert conn.status != 401
    end
  end

  describe "auth enabled — invalid key" do
    test "halts with 401 when key is wrong" do
      Application.put_env(:edge_admin, :master_key, "secret-master-key")
      conn = "Bearer wrong-key" |> build_conn() |> MasterKeyAuth.call(@opts)
      assert conn.halted
      assert conn.status == 401
    end

    test "halts with 401 when no Authorization header" do
      Application.put_env(:edge_admin, :master_key, "secret-master-key")
      conn = nil |> build_conn() |> MasterKeyAuth.call(@opts)
      assert conn.halted
      assert conn.status == 401
    end

    test "halts with 401 when scheme is not Bearer" do
      Application.put_env(:edge_admin, :master_key, "secret-master-key")
      conn = "Token secret-master-key" |> build_conn() |> MasterKeyAuth.call(@opts)
      assert conn.halted
      assert conn.status == 401
    end

    test "halts with 401 when key has extra whitespace" do
      Application.put_env(:edge_admin, :master_key, "secret-master-key")
      conn = "Bearer secret-master-key " |> build_conn() |> MasterKeyAuth.call(@opts)
      assert conn.halted
      assert conn.status == 401
    end

    test "halts with 401 when Authorization is empty string" do
      Application.put_env(:edge_admin, :master_key, "secret-master-key")
      conn = "" |> build_conn() |> MasterKeyAuth.call(@opts)
      assert conn.halted
      assert conn.status == 401
    end

    test "response body contains error key" do
      Application.put_env(:edge_admin, :master_key, "secret-master-key")
      conn = "Bearer wrong" |> build_conn() |> MasterKeyAuth.call(@opts)
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "error")
    end
  end

  describe "auth_enabled defaults to true" do
    test "when :auth_enabled not set, auth is enforced" do
      Application.delete_env(:edge_admin, :auth_enabled)
      Application.put_env(:edge_admin, :master_key, "secret")
      conn = nil |> build_conn() |> MasterKeyAuth.call(@opts)
      assert conn.halted
      assert conn.status == 401
    end
  end
end
