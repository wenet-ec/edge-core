# nexmaker/test/nexmaker/api_unit_test.exs
#
# Unit tests for Nexmaker.Api.normalize/1.
# Pure logic — no live Netmaker connection required.
defmodule Nexmaker.ApiUnitTest do
  use ExUnit.Case, async: true

  describe "Nexmaker.Api.normalize/1" do
    test "pass-through for {:ok, result}" do
      assert Nexmaker.Api.normalize({:ok, %{"netid" => "cluster-prod"}}) ==
               {:ok, %{"netid" => "cluster-prod"}}
    end

    test "pass-through for {:ok, nil}" do
      assert Nexmaker.Api.normalize({:ok, nil}) == {:ok, nil}
    end

    test "pass-through for {:ok, list}" do
      assert Nexmaker.Api.normalize({:ok, [1, 2, 3]}) == {:ok, [1, 2, 3]}
    end

    test "pass-through for {:error, :not_found}" do
      assert Nexmaker.Api.normalize({:error, :not_found}) == {:error, :not_found}
    end

    test "pass-through for {:error, :conflict}" do
      assert Nexmaker.Api.normalize({:error, :conflict}) == {:error, :conflict}
    end

    test "pass-through for {:error, {:bad_request, body}}" do
      body = %{"Message" => "invalid cidr"}

      assert Nexmaker.Api.normalize({:error, {:bad_request, body}}) ==
               {:error, {:bad_request, body}}
    end

    test "400 http_error -> {:error, {:bad_request, body}}" do
      body = %{"Message" => "invalid cidr"}

      assert Nexmaker.Api.normalize({:error, {:http_error, 400, body}}) ==
               {:error, {:bad_request, body}}
    end

    test "400 with binary body -> {:error, {:bad_request, binary}}" do
      assert Nexmaker.Api.normalize({:error, {:http_error, 400, "bad input"}}) ==
               {:error, {:bad_request, "bad input"}}
    end

    test "404 http_error -> {:error, :not_found}" do
      assert Nexmaker.Api.normalize({:error, {:http_error, 404, %{"Message" => "not found"}}}) ==
               {:error, :not_found}
    end

    test "409 http_error -> {:error, :conflict}" do
      assert Nexmaker.Api.normalize({:error, {:http_error, 409, %{"Message" => "conflict"}}}) ==
               {:error, :conflict}
    end

    test "500 with 'no result found' body -> {:error, :not_found}" do
      body = %{"Message" => "no result found"}
      assert Nexmaker.Api.normalize({:error, {:http_error, 500, body}}) == {:error, :not_found}
    end

    test "500 with 'could not find any records' body -> {:error, :not_found}" do
      body = %{"Message" => "could not find any records"}
      assert Nexmaker.Api.normalize({:error, {:http_error, 500, body}}) == {:error, :not_found}
    end

    test "500 with 'no result found' embedded in longer message -> {:error, :not_found}" do
      body = %{"Message" => "error: no result found for key xyz"}
      assert Nexmaker.Api.normalize({:error, {:http_error, 500, body}}) == {:error, :not_found}
    end

    test "500 with 'host already part of network' body -> {:error, :already_exists}" do
      body = %{"Message" => "host already part of network cluster-prod"}

      assert Nexmaker.Api.normalize({:error, {:http_error, 500, body}}) ==
               {:error, :already_exists}
    end

    test "500 with unrecognized body -> {:error, :service_unavailable}" do
      body = %{"Message" => "internal server error"}

      assert Nexmaker.Api.normalize({:error, {:http_error, 500, body}}) ==
               {:error, :service_unavailable}
    end

    test "500 with binary body not matching known patterns -> {:error, :service_unavailable}" do
      assert Nexmaker.Api.normalize({:error, {:http_error, 500, "something went wrong"}}) ==
               {:error, :service_unavailable}
    end

    test "500 with binary body matching 'no result found' -> {:error, :not_found}" do
      assert Nexmaker.Api.normalize({:error, {:http_error, 500, "no result found"}}) ==
               {:error, :not_found}
    end

    test "500 with nil body -> {:error, :service_unavailable}" do
      assert Nexmaker.Api.normalize({:error, {:http_error, 500, nil}}) ==
               {:error, :service_unavailable}
    end

    test "503 http_error -> {:error, :service_unavailable}" do
      assert Nexmaker.Api.normalize({:error, {:http_error, 503, %{"Message" => "unavailable"}}}) ==
               {:error, :service_unavailable}
    end

    test "network/transport error -> {:error, :service_unavailable}" do
      assert Nexmaker.Api.normalize({:error, {:http_client_error, :econnrefused}}) ==
               {:error, :service_unavailable}
    end

    test "arbitrary error atom -> {:error, :service_unavailable}" do
      assert Nexmaker.Api.normalize({:error, :timeout}) == {:error, :service_unavailable}
    end
  end

  # ---------------------------------------------------------------------------
  # extract_message/1 — pulls the Netmaker error string out of the response
  # body. Three input shapes (map / binary / anything else); the return is
  # always a string. Used by normalize/1 to classify 500 responses.
  # ---------------------------------------------------------------------------

  describe "Nexmaker.Api.extract_message/1" do
    test "map with Message key returns the message string" do
      assert Nexmaker.Api.extract_message(%{"Message" => "no result found"}) ==
               "no result found"
    end

    test "map without Message key returns empty string (not nil)" do
      assert Nexmaker.Api.extract_message(%{"Code" => 500}) == ""
    end

    test "empty map returns empty string" do
      assert Nexmaker.Api.extract_message(%{}) == ""
    end

    test "binary body is returned as-is (some endpoints return raw text)" do
      assert Nexmaker.Api.extract_message("internal error") == "internal error"
    end

    test "empty binary returns empty binary" do
      assert Nexmaker.Api.extract_message("") == ""
    end

    test "non-map, non-binary inputs fall through to empty string (defensive)" do
      assert Nexmaker.Api.extract_message(nil) == ""
      assert Nexmaker.Api.extract_message(123) == ""
      assert Nexmaker.Api.extract_message([1, 2, 3]) == ""
      assert Nexmaker.Api.extract_message(:atom) == ""
    end

    test "ignores other map keys (only Message is consulted)" do
      body = %{"Message" => "the message", "Code" => 500, "extra" => "ignored"}
      assert Nexmaker.Api.extract_message(body) == "the message"
    end
  end

  # ---------------------------------------------------------------------------
  # build_url/3 — composes the request URL. Trailing-slash trim + query
  # encoding are subtle contracts every API call relies on. Tests pin both.
  # ---------------------------------------------------------------------------

  describe "Nexmaker.Api.build_url/3" do
    test "concatenates base + path when no query is given" do
      assert Nexmaker.Api.build_url("http://netmaker:8081", "/api/networks", []) ==
               "http://netmaker:8081/api/networks"
    end

    test "trims a single trailing slash from base_url (callers can configure either form)" do
      assert Nexmaker.Api.build_url("http://netmaker:8081/", "/api/networks", []) ==
               "http://netmaker:8081/api/networks"
    end

    test "trims any number of trailing slashes (String.trim_trailing semantics)" do
      # Pin the actual behaviour: a base_url with multiple trailing slashes
      # collapses entirely. Drift here would silently change URLs.
      assert Nexmaker.Api.build_url("http://netmaker:8081///", "/api/networks", []) ==
               "http://netmaker:8081/api/networks"
    end

    test "appends ?key=value when a query keyword is given" do
      url = Nexmaker.Api.build_url("http://netmaker:8081", "/api/v1/acls", network: "cluster-a")

      assert url == "http://netmaker:8081/api/v1/acls?network=cluster-a"
    end

    test "URL-encodes query values (so spaces and special chars survive transport)" do
      url =
        Nexmaker.Api.build_url("http://netmaker:8081", "/api/networks",
          name: "my cluster",
          tag: "a&b"
        )

      assert url =~ "name=my+cluster"
      assert url =~ "tag=a%26b"
    end

    test "preserves the order of multiple query params" do
      url = Nexmaker.Api.build_url("http://x", "/p", a: "1", b: "2", c: "3")

      assert url == "http://x/p?a=1&b=2&c=3"
    end

    test "empty query keyword list takes the no-query path (no trailing ?)" do
      assert Nexmaker.Api.build_url("http://x", "/p", []) == "http://x/p"
    end

    test "path is appended verbatim (no smart slash insertion)" do
      # If base_url has no trailing slash AND path doesn't start with one,
      # the result is concatenated as-is. Drift here would silently produce
      # malformed URLs — pin the intentional concat-as-is behaviour.
      assert Nexmaker.Api.build_url("http://x", "raw-path", []) == "http://xraw-path"
    end
  end
end
