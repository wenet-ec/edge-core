# edge_admin/test/edge_admin/config_test.exs
defmodule EdgeAdmin.ConfigTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Config

  # ---------------------------------------------------------------------------
  # Helpers — inject a known env var value without polluting the process env
  # ---------------------------------------------------------------------------

  # We use a unique key per test to avoid collisions when running async.
  defp with_env(key, value, fun) do
    System.put_env(key, value)

    try do
      fun.()
    after
      System.delete_env(key)
    end
  end

  # ---------------------------------------------------------------------------
  # get_env/3 — default when env var is missing
  # ---------------------------------------------------------------------------

  describe "get_env/3 — missing env var" do
    test "returns nil default when var not set" do
      key = "EDGE_TEST_MISSING_#{System.unique_integer([:positive])}"
      assert Config.get_env(key) == nil
    end

    test "returns provided default when var not set" do
      key = "EDGE_TEST_MISSING_#{System.unique_integer([:positive])}"
      assert Config.get_env(key, :string, "fallback") == "fallback"
    end

    test "returns integer default when var not set" do
      key = "EDGE_TEST_MISSING_#{System.unique_integer([:positive])}"
      assert Config.get_env(key, :integer, 42) == 42
    end
  end

  # ---------------------------------------------------------------------------
  # get_env/3 — :string type
  # ---------------------------------------------------------------------------

  describe "get_env/3 — :string type" do
    test "returns value as-is" do
      key = "EDGE_TEST_STR_#{System.unique_integer([:positive])}"

      with_env(key, "hello world", fn ->
        assert Config.get_env(key, :string) == "hello world"
      end)
    end

    test "default type is :string" do
      key = "EDGE_TEST_STR_#{System.unique_integer([:positive])}"

      with_env(key, "plain", fn ->
        assert Config.get_env(key) == "plain"
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # get_env/3 — :integer type
  # ---------------------------------------------------------------------------

  describe "get_env/3 — :integer type" do
    test "parses positive integer string" do
      key = "EDGE_TEST_INT_#{System.unique_integer([:positive])}"

      with_env(key, "42", fn ->
        assert Config.get_env(key, :integer) == 42
      end)
    end

    test "parses zero" do
      key = "EDGE_TEST_INT_#{System.unique_integer([:positive])}"

      with_env(key, "0", fn ->
        assert Config.get_env(key, :integer) == 0
      end)
    end

    test "parses negative integer string" do
      key = "EDGE_TEST_INT_#{System.unique_integer([:positive])}"

      with_env(key, "-5", fn ->
        assert Config.get_env(key, :integer) == -5
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # get_env/3 — :boolean type
  # ---------------------------------------------------------------------------

  describe "get_env/3 — :boolean type" do
    test "value 'true' returns true" do
      key = "EDGE_TEST_BOOL_#{System.unique_integer([:positive])}"

      with_env(key, "true", fn ->
        assert Config.get_env(key, :boolean) == true
      end)
    end

    test "value '1' returns true" do
      key = "EDGE_TEST_BOOL_#{System.unique_integer([:positive])}"

      with_env(key, "1", fn ->
        assert Config.get_env(key, :boolean) == true
      end)
    end

    test "value 'TRUE' uppercase returns true" do
      key = "EDGE_TEST_BOOL_#{System.unique_integer([:positive])}"

      with_env(key, "TRUE", fn ->
        assert Config.get_env(key, :boolean) == true
      end)
    end

    test "value 'false' returns false" do
      key = "EDGE_TEST_BOOL_#{System.unique_integer([:positive])}"

      with_env(key, "false", fn ->
        assert Config.get_env(key, :boolean) == false
      end)
    end

    test "value '0' returns false" do
      key = "EDGE_TEST_BOOL_#{System.unique_integer([:positive])}"

      with_env(key, "0", fn ->
        assert Config.get_env(key, :boolean) == false
      end)
    end

    test "any other string -> false" do
      key = "EDGE_TEST_BOOL_#{System.unique_integer([:positive])}"

      with_env(key, "yes", fn ->
        assert Config.get_env(key, :boolean) == false
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # get_env/3 — :cors type
  # ---------------------------------------------------------------------------

  describe "get_env/3 — :cors type" do
    test "single origin returns string" do
      key = "EDGE_TEST_CORS_#{System.unique_integer([:positive])}"

      with_env(key, "https://example.com", fn ->
        assert Config.get_env(key, :cors) == "https://example.com"
      end)
    end

    test "comma-separated origins returns list" do
      key = "EDGE_TEST_CORS_#{System.unique_integer([:positive])}"

      with_env(key, "https://a.com,https://b.com", fn ->
        assert Config.get_env(key, :cors) == ["https://a.com", "https://b.com"]
      end)
    end

    test "three origins returns list of three" do
      key = "EDGE_TEST_CORS_#{System.unique_integer([:positive])}"

      with_env(key, "https://a.com,https://b.com,https://c.com", fn ->
        result = Config.get_env(key, :cors)
        assert result == ["https://a.com", "https://b.com", "https://c.com"]
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # get_env/3 — :uri type
  # ---------------------------------------------------------------------------

  describe "get_env/3 — :uri type" do
    test "parses URI string into URI struct" do
      key = "EDGE_TEST_URI_#{System.unique_integer([:positive])}"

      with_env(key, "http://localhost:4000", fn ->
        result = Config.get_env(key, :uri)
        assert %URI{} = result
        assert result.scheme == "http"
        assert result.host == "localhost"
        assert result.port == 4000
      end)
    end

    test "empty string returns nil" do
      key = "EDGE_TEST_URI_#{System.unique_integer([:positive])}"

      with_env(key, "", fn ->
        assert Config.get_env(key, :uri) == nil
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # get_env/3 — :list type
  # ---------------------------------------------------------------------------

  describe "get_env/3 — :list type" do
    test "comma-separated string returns trimmed list" do
      key = "EDGE_TEST_LIST_#{System.unique_integer([:positive])}"

      with_env(key, "a, b, c", fn ->
        assert Config.get_env(key, :list) == ["a", "b", "c"]
      end)
    end

    test "single value returns single-element list" do
      key = "EDGE_TEST_LIST_#{System.unique_integer([:positive])}"

      with_env(key, "only", fn ->
        assert Config.get_env(key, :list) == ["only"]
      end)
    end

    test "empty string returns empty list" do
      key = "EDGE_TEST_LIST_#{System.unique_integer([:positive])}"

      with_env(key, "", fn ->
        assert Config.get_env(key, :list) == []
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # get_env/3 — :atom type
  # ---------------------------------------------------------------------------

  describe "get_env/3 — :atom type" do
    test "converts string to atom" do
      key = "EDGE_TEST_ATOM_#{System.unique_integer([:positive])}"
      # Use an atom that already exists in the system to avoid creating new ones
      with_env(key, "ok", fn ->
        assert Config.get_env(key, :atom) == :ok
      end)
    end

    test "converts known atom string" do
      key = "EDGE_TEST_ATOM_#{System.unique_integer([:positive])}"

      with_env(key, "error", fn ->
        assert Config.get_env(key, :atom) == :error
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # get_env/3 — :positive_integer type
  # ---------------------------------------------------------------------------

  describe "get_env/3 — :positive_integer type" do
    test "parses positive integer string" do
      key = "EDGE_TEST_POSINT_#{System.unique_integer([:positive])}"

      with_env(key, "10", fn ->
        assert Config.get_env(key, :positive_integer) == 10
      end)
    end

    test "boundary: 1 is accepted" do
      key = "EDGE_TEST_POSINT_#{System.unique_integer([:positive])}"

      with_env(key, "1", fn ->
        assert Config.get_env(key, :positive_integer) == 1
      end)
    end

    test "zero raises ArgumentError" do
      key = "EDGE_TEST_POSINT_#{System.unique_integer([:positive])}"

      with_env(key, "0", fn ->
        assert_raise ArgumentError, ~r/positive integer/, fn ->
          Config.get_env(key, :positive_integer)
        end
      end)
    end

    test "negative value raises ArgumentError" do
      key = "EDGE_TEST_POSINT_#{System.unique_integer([:positive])}"

      with_env(key, "-1", fn ->
        assert_raise ArgumentError, ~r/positive integer/, fn ->
          Config.get_env(key, :positive_integer)
        end
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # generate_random_string/1
  # ---------------------------------------------------------------------------

  describe "generate_random_string/1" do
    test "returns string of exact requested length" do
      assert String.length(Config.generate_random_string(16)) == 16
      assert String.length(Config.generate_random_string(32)) == 32
      assert String.length(Config.generate_random_string(64)) == 64
    end

    test "returns only lowercase base32 characters (a-z, 2-7)" do
      result = Config.generate_random_string(100)
      assert result =~ ~r/^[a-z2-7]+$/
    end

    test "two calls produce different results" do
      a = Config.generate_random_string(32)
      b = Config.generate_random_string(32)
      assert a != b
    end

    test "length 1 works" do
      result = Config.generate_random_string(1)
      assert String.length(result) == 1
      assert result =~ ~r/^[a-z2-7]$/
    end
  end
end
