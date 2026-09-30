# edge_admin/test/edge_admin/vpn/api_test.exs
defmodule EdgeAdmin.Vpn.ApiTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Vpn.Api

  describe "normalize_error/1" do
    test "preserves successful results and not-found errors" do
      assert Api.normalize_error({:ok, %{"netid" => "x"}}) == {:ok, %{"netid" => "x"}}
      assert Api.normalize_error({:ok, []}) == {:ok, []}
      assert Api.normalize_error({:error, :not_found}) == {:error, :not_found}
    end

    test "normalizes other failures to service unavailable" do
      errors = [:timeout, :econnrefused, %{status: 500}, "anything", :conflict, {:bad_request, %{"Message" => "x"}}]

      for error <- errors do
        assert Api.normalize_error({:error, error}) == {:error, :service_unavailable}
      end
    end
  end
end
