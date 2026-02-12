defmodule EdgeAdminWeb.Plugs.ApiDocsEnabledTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias EdgeAdminWeb.Plugs.ApiDocsEnabled

  @opts ApiDocsEnabled.init([])

  setup do
    on_exit(fn ->
      Application.delete_env(:edge_admin, :api_docs_enabled)
    end)
  end

  describe "api docs enabled" do
    test "passes through when explicitly set to true" do
      Application.put_env(:edge_admin, :api_docs_enabled, true)
      conn = :get |> conn("/api/openapi") |> ApiDocsEnabled.call(@opts)
      refute conn.halted
    end

    test "passes through when not configured (defaults to true)" do
      Application.delete_env(:edge_admin, :api_docs_enabled)
      conn = :get |> conn("/api/openapi") |> ApiDocsEnabled.call(@opts)
      refute conn.halted
    end

    test "does not set response status when passing through" do
      Application.put_env(:edge_admin, :api_docs_enabled, true)
      conn = :get |> conn("/api/openapi") |> ApiDocsEnabled.call(@opts)
      # Status not set by plug (remains 0 from build_conn)
      refute conn.status == 404
    end
  end

  describe "api docs disabled" do
    test "halts with 404 when set to false" do
      Application.put_env(:edge_admin, :api_docs_enabled, false)
      conn = :get |> conn("/api/openapi") |> ApiDocsEnabled.call(@opts)
      assert conn.halted
      assert conn.status == 404
    end

    test "response is JSON content-type" do
      Application.put_env(:edge_admin, :api_docs_enabled, false)
      conn = :get |> conn("/api/openapi") |> ApiDocsEnabled.call(@opts)
      assert conn |> get_resp_header("content-type") |> hd() =~ "application/json"
    end

    test "response body is JSON with errors key" do
      Application.put_env(:edge_admin, :api_docs_enabled, false)
      conn = :get |> conn("/swaggerui") |> ApiDocsEnabled.call(@opts)
      body = Jason.decode!(conn.resp_body)
      assert %{"errors" => %{"detail" => "Not Found"}} = body
    end

    test "path does not affect the outcome — /redoc also blocked" do
      Application.put_env(:edge_admin, :api_docs_enabled, false)
      conn = :get |> conn("/redoc") |> ApiDocsEnabled.call(@opts)
      assert conn.halted
      assert conn.status == 404
    end

    test "path does not affect the outcome — /swaggerui also blocked" do
      Application.put_env(:edge_admin, :api_docs_enabled, false)
      conn = :get |> conn("/swaggerui") |> ApiDocsEnabled.call(@opts)
      assert conn.halted
      assert conn.status == 404
    end
  end
end
