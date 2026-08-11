# edge_admin/test/edge_admin/password_hashers_test.exs
defmodule EdgeAdmin.PasswordHashersTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.PasswordHashers

  defmodule CurrentHasher do
    @moduledoc false
    @behaviour PasswordHashers

    def matches?("current:" <> _), do: true
    def matches?(_), do: false
    def hash(password), do: "current:" <> password
    def verify(password, "current:" <> candidate), do: password == candidate
  end

  defmodule LegacyHasher do
    @moduledoc false
    @behaviour PasswordHashers

    def matches?("legacy:" <> _), do: true
    def matches?(_), do: false
    def hash(password), do: "legacy:" <> password
    def verify(password, "legacy:" <> candidate), do: password == candidate
  end

  test "the first hasher creates new hashes and verifies them as current" do
    hashers = [CurrentHasher, LegacyHasher]

    assert PasswordHashers.hash_with("secret", hashers) == "current:secret"
    assert PasswordHashers.verify_with("secret", "current:secret", hashers) == {:ok, :current}
  end

  test "a retained hasher verifies legacy hashes and marks them for migration" do
    hashers = [CurrentHasher, LegacyHasher]

    assert PasswordHashers.verify_with("secret", "legacy:secret", hashers) == {:ok, :legacy}
  end

  test "unknown formats and incorrect passwords never verify" do
    hashers = [CurrentHasher, LegacyHasher]

    assert PasswordHashers.verify_with("wrong", "legacy:secret", hashers) == :error
    assert PasswordHashers.verify_with("secret", "unrecognized:secret", hashers) == :error
  end
end
