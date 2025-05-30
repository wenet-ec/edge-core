# test/edge_admin/factory_test.exs
defmodule EdgeAdmin.FactoryTest do
  @moduledoc """
  This is a test module to make sure our factory setup is working correctly.
  You'll probably want to delete it.
  """

  use EdgeAdmin.DataCase, async: true

  import EdgeAdmin.Factory

  test "name factory returns a string" do
    # Since name_factory returns a string directly, just call it directly
    assert is_binary(name_factory())
  end

  test "email factory returns a string" do
    assert is_binary(email_factory())
  end

  test "uuid factory returns a valid UUID" do
    uuid = uuid_factory()
    assert is_binary(uuid)
    assert String.length(uuid) == 36
  end

  test "api_request_params factory returns proper structure" do
    params = build(:api_request_params)
    assert is_map(params)
    assert Map.has_key?(params, "data")
    assert is_map(params["data"])
  end
end
