# edge_admin/test/edge_admin_web/plugs/redoc_ui_test.exs
defmodule EdgeAdminWeb.Plugs.RedocUITest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias EdgeAdminWeb.Plugs.RedocUI

  # ---------------------------------------------------------------------------
  # init/1 — validates that the route is wired with the hardcoded spec_url, so
  # a misconfigured router crashes at boot rather than serving a broken page.
  # ---------------------------------------------------------------------------

  describe "init/1" do
    test "accepts no spec_url (route mounted bare)" do
      assert RedocUI.init([]) == :ok
    end

    test "accepts the documented spec_url" do
      assert RedocUI.init(spec_url: "/api/openapi") == :ok
    end

    test "raises on a mismatched spec_url" do
      assert_raise ArgumentError, ~r"hardcoded to spec_url=/api/openapi", fn ->
        RedocUI.init(spec_url: "/api/v2/openapi")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # call/2 — sends the precomputed HTML with content-type text/html
  # ---------------------------------------------------------------------------

  describe "call/2" do
    test "returns 200 with HTML content-type" do
      conn = :get |> conn("/redoc") |> RedocUI.call([])

      assert conn.status == 200
      assert {"content-type", "text/html; charset=utf-8"} in conn.resp_headers
    end

    test "body references the documented spec URL" do
      conn = :get |> conn("/redoc") |> RedocUI.call([])

      assert conn.resp_body =~ ~s(spec-url="/api/openapi")
    end

    test "body references the ReDoc CDN bundle" do
      conn = :get |> conn("/redoc") |> RedocUI.call([])

      assert conn.resp_body =~ "cdn.jsdelivr.net"
      assert conn.resp_body =~ "redoc.standalone.js"
    end

    test "body carries the brand theme JSON" do
      conn = :get |> conn("/redoc") |> RedocUI.call([])

      # Navy brand color appears in the theme JSON. Pin one constant so a
      # theme-stripping regression is visible.
      assert conn.resp_body =~ "#3e567c"
    end

    test "body is identical across calls (precomputed HTML, no per-request interpolation)" do
      a = :get |> conn("/redoc") |> RedocUI.call([])
      b = :get |> conn("/redoc?foo=bar") |> RedocUI.call([])

      assert a.resp_body == b.resp_body
    end
  end
end
