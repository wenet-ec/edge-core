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
end
