# edge_admin/test/edge_admin_web/plugs/strip_request_logger_param_test.exs
defmodule EdgeAdminWeb.Plugs.StripRequestLoggerParamTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias EdgeAdminWeb.Plugs.StripRequestLoggerParam

  @opts StripRequestLoggerParam.init([])

  # ---------------------------------------------------------------------------
  # query_params Unfetched → pass through unchanged
  # ---------------------------------------------------------------------------

  describe "call/2 — query_params not yet fetched" do
    test "returns the conn unchanged" do
      # Plug.Test.conn/2 leaves query_params as %Plug.Conn.Unfetched{} until
      # fetch_query_params/1 is called.
      conn = conn(:get, "/?request_logger=abc&page=2")

      assert %Plug.Conn.Unfetched{} = conn.query_params

      result = StripRequestLoggerParam.call(conn, @opts)

      assert result == conn
    end
  end

  # ---------------------------------------------------------------------------
  # query_params present, no request_logger → pass through unchanged
  # ---------------------------------------------------------------------------

  describe "call/2 — request_logger absent" do
    test "returns the conn unchanged when no request_logger param is present" do
      conn = :get |> conn("/?page=2") |> Plug.Conn.fetch_query_params()

      result = StripRequestLoggerParam.call(conn, @opts)

      assert result.query_params == conn.query_params
      assert result.params == conn.params
    end
  end

  # ---------------------------------------------------------------------------
  # request_logger present → strip from query_params, params, and query_string
  # ---------------------------------------------------------------------------

  describe "call/2 — request_logger present" do
    test "drops request_logger from query_params" do
      conn = :get |> conn("/?request_logger=abc&page=2") |> Plug.Conn.fetch_query_params()

      result = StripRequestLoggerParam.call(conn, @opts)

      refute Map.has_key?(result.query_params, "request_logger")
      assert result.query_params["page"] == "2"
    end

    test "drops request_logger from params (so OpenApiSpex CastAndValidate doesn't see it)" do
      conn = :get |> conn("/?request_logger=abc&page=2") |> Plug.Conn.fetch_query_params()

      result = StripRequestLoggerParam.call(conn, @opts)

      refute Map.has_key?(result.params, "request_logger")
      assert result.params["page"] == "2"
    end

    test "rebuilds query_string without request_logger" do
      conn = :get |> conn("/?request_logger=abc&page=2") |> Plug.Conn.fetch_query_params()

      result = StripRequestLoggerParam.call(conn, @opts)

      refute result.query_string =~ "request_logger"
      assert result.query_string =~ "page=2"
    end

    test "preserves other query params verbatim" do
      conn =
        :get
        |> conn("/?request_logger=abc&page=2&filter=active")
        |> Plug.Conn.fetch_query_params()

      result = StripRequestLoggerParam.call(conn, @opts)

      assert result.query_params == %{"page" => "2", "filter" => "active"}
    end

    test "removes the only param when request_logger is alone" do
      conn = :get |> conn("/?request_logger=abc") |> Plug.Conn.fetch_query_params()

      result = StripRequestLoggerParam.call(conn, @opts)

      assert result.query_params == %{}
      assert result.query_string == ""
    end
  end
end
