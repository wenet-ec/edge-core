# edge_admin/test/edge_admin/random_test.exs
defmodule EdgeAdmin.RandomTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Random

  test "token is 32 random bytes encoded as unpadded Base64" do
    token = Random.token()

    assert {:ok, <<_::binary-size(32)>>} = Base.decode64(token, padding: false)
    refute String.ends_with?(token, "=")
  end

  test "string returns the requested lowercase Base32 length" do
    value = Random.string(32)

    assert String.length(value) == 32
    assert value =~ ~r/\A[a-z2-7]+\z/
  end
end
