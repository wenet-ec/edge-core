# edge_admin/test/edge_admin_web/plugs/agent_auth_test.exs
defmodule EdgeAdminWeb.Plugs.AgentAuthTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias EdgeAdminWeb.Plugs.AgentAuth

  defp stub_node(id \\ "node-abc123") do
    %{id: id, cluster: %{name: "cluster-test"}}
  end

  defp lookup_returning(result) do
    fn _token -> result end
  end

  defp opts_with(lookup), do: AgentAuth.init(node_lookup: lookup)

  defp build_conn(nil), do: conn(:get, "/")
  defp build_conn(header), do: :get |> conn("/") |> put_req_header("authorization", header)

  describe "missing or malformed Authorization header" do
    test "halts with 401 when no header" do
      opts = opts_with(lookup_returning({:ok, stub_node()}))
      conn = nil |> build_conn() |> AgentAuth.call(opts)
      assert conn.halted
      assert conn.status == 401
    end

    test "halts with 401 when scheme is not Bearer" do
      opts = opts_with(lookup_returning({:ok, stub_node()}))
      conn = "Token some-token" |> build_conn() |> AgentAuth.call(opts)
      assert conn.halted
      assert conn.status == 401
    end

    test "halts with 401 when Authorization is empty string" do
      opts = opts_with(lookup_returning({:ok, stub_node()}))
      conn = "" |> build_conn() |> AgentAuth.call(opts)
      assert conn.halted
      assert conn.status == 401
    end

    test "response body contains error key" do
      opts = opts_with(lookup_returning({:ok, stub_node()}))
      conn = nil |> build_conn() |> AgentAuth.call(opts)
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "error")
    end
  end

  describe "valid Bearer token — lookup succeeds" do
    test "passes through and assigns current_node" do
      node = stub_node("node-xyz")
      opts = opts_with(lookup_returning({:ok, node}))
      conn = "Bearer valid-token" |> build_conn() |> AgentAuth.call(opts)
      refute conn.halted
      assert conn.assigns.current_node == node
    end

    test "lookup receives the token from the header" do
      received = fn -> nil end |> Agent.start_link() |> elem(1)

      lookup = fn token ->
        Agent.update(received, fn _ -> token end)
        {:ok, stub_node()}
      end

      opts = AgentAuth.init(node_lookup: lookup)
      "Bearer my-secret-token" |> build_conn() |> AgentAuth.call(opts)
      assert Agent.get(received, & &1) == "my-secret-token"
    end

    test "does not halt connection" do
      opts = opts_with(lookup_returning({:ok, stub_node()}))
      conn = "Bearer any-token" |> build_conn() |> AgentAuth.call(opts)
      refute conn.halted
    end
  end

  describe "valid Bearer token — lookup fails" do
    test "halts with 401 when token not found" do
      opts = opts_with(lookup_returning(:error))
      conn = "Bearer unknown-token" |> build_conn() |> AgentAuth.call(opts)
      assert conn.halted
      assert conn.status == 401
    end

    test "response body contains error key" do
      opts = opts_with(lookup_returning(:error))
      conn = "Bearer unknown-token" |> build_conn() |> AgentAuth.call(opts)
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "error")
    end
  end

  describe "default init (no opts)" do
    test "init with no args returns the default lookup function" do
      result = AgentAuth.init([])
      assert is_function(result, 1)
    end
  end
end
