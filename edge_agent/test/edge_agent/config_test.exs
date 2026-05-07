# edge_agent/test/edge_agent/config_test.exs
defmodule EdgeAgent.ConfigTest do
  # async: false — tests mutate System env. Each test snapshot/restores its
  # specific key so adjacent tests don't cross-talk, but the env itself is
  # process-global.
  use ExUnit.Case, async: false

  alias EdgeAgent.Config

  # Pick a key that's vanishingly unlikely to be set in CI / dev environments.
  @key "EDGE_AGENT_CONFIG_TEST_KEY"

  defp with_env(value, fun) do
    previous = System.get_env(@key)

    if is_nil(value), do: System.delete_env(@key), else: System.put_env(@key, value)

    try do
      fun.()
    after
      case previous do
        nil -> System.delete_env(@key)
        v -> System.put_env(@key, v)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # get_env/1 — soft read, default :string type
  # ---------------------------------------------------------------------------

  describe "get_env/1" do
    test "returns the value when set" do
      with_env("hello", fn -> assert Config.get_env(@key) == "hello" end)
    end

    test "returns nil when unset" do
      with_env(nil, fn -> assert Config.get_env(@key) == nil end)
    end

    test "preserves whitespace and case verbatim" do
      with_env("  Mixed Case  ", fn -> assert Config.get_env(@key) == "  Mixed Case  " end)
    end
  end

  # ---------------------------------------------------------------------------
  # get_env/2 — explicit type, no default
  # ---------------------------------------------------------------------------

  describe "get_env/2 — :string" do
    test "returns the raw string when set" do
      with_env("xyz", fn -> assert Config.get_env(@key, :string) == "xyz" end)
    end

    test "returns nil when unset" do
      with_env(nil, fn -> assert Config.get_env(@key, :string) == nil end)
    end
  end

  describe "get_env/2 — :integer" do
    test "parses integer string" do
      with_env("42", fn -> assert Config.get_env(@key, :integer) == 42 end)
    end

    test "raises when unset (no default supplied)" do
      with_env(nil, fn ->
        # Documents actual behaviour: get_env/2 with :integer feeds nil to
        # String.to_integer, which raises ArgumentError ("not a binary").
        # Use get_env/3 with a default if the var is optional.
        assert_raise ArgumentError, fn -> Config.get_env(@key, :integer) end
      end)
    end

    test "raises on non-numeric input" do
      with_env("not a number", fn ->
        assert_raise ArgumentError, fn -> Config.get_env(@key, :integer) end
      end)
    end
  end

  describe "get_env/2 — :boolean" do
    test "'true' (any case) → true" do
      for v <- ["true", "TRUE", "True", "tRuE"] do
        with_env(v, fn ->
          assert Config.get_env(@key, :boolean) == true,
                 "expected #{inspect(v)} to be truthy"
        end)
      end
    end

    test "'1' → true" do
      with_env("1", fn -> assert Config.get_env(@key, :boolean) == true end)
    end

    test "'false', '0', and other strings → false" do
      for v <- ["false", "FALSE", "0", "no", "off", "yes", "anything"] do
        with_env(v, fn ->
          assert Config.get_env(@key, :boolean) == false,
                 "expected #{inspect(v)} to be falsy"
        end)
      end
    end

    test "nil → false" do
      with_env(nil, fn -> assert Config.get_env(@key, :boolean) == false end)
    end

    test "empty string → false" do
      with_env("", fn -> assert Config.get_env(@key, :boolean) == false end)
    end
  end

  describe "get_env/2 — :uri" do
    test "parses a valid URI" do
      with_env("https://admin.example.com/path", fn ->
        result = Config.get_env(@key, :uri)
        assert %URI{} = result
        assert result.scheme == "https"
        assert result.host == "admin.example.com"
        assert result.path == "/path"
      end)
    end

    test "nil → nil" do
      with_env(nil, fn -> assert Config.get_env(@key, :uri) == nil end)
    end

    test "empty string → nil" do
      with_env("", fn -> assert Config.get_env(@key, :uri) == nil end)
    end
  end

  describe "get_env/2 — :cors" do
    test "single token returns a string (not a list)" do
      with_env("https://app.example.com", fn ->
        assert Config.get_env(@key, :cors) == "https://app.example.com"
      end)
    end

    test "comma-separated tokens return a list" do
      with_env("https://a.example.com,https://b.example.com", fn ->
        assert Config.get_env(@key, :cors) == [
                 "https://a.example.com",
                 "https://b.example.com"
               ]
      end)
    end

    test "nil → nil" do
      with_env(nil, fn -> assert Config.get_env(@key, :cors) == nil end)
    end

    test "empty string returns the empty string (single 'token')" do
      # Documents actual behaviour: split("", ",") → [""], so the
      # single-token branch fires and returns "". Worth pinning so a
      # refactor to "treat empty as nil" is a deliberate decision.
      with_env("", fn -> assert Config.get_env(@key, :cors) == "" end)
    end
  end

  describe "get_env/2 — :list" do
    test "splits comma-separated values, trimming whitespace" do
      with_env("a, b ,c", fn ->
        assert Config.get_env(@key, :list) == ["a", "b", "c"]
      end)
    end

    test "single value returns a one-element list" do
      with_env("only", fn -> assert Config.get_env(@key, :list) == ["only"] end)
    end

    test "nil → []" do
      with_env(nil, fn -> assert Config.get_env(@key, :list) == [] end)
    end

    test "empty string → []" do
      with_env("", fn -> assert Config.get_env(@key, :list) == [] end)
    end
  end

  # ---------------------------------------------------------------------------
  # get_env/3 — soft read with default
  # ---------------------------------------------------------------------------

  describe "get_env/3" do
    test "uses the default when var is unset" do
      with_env(nil, fn ->
        assert Config.get_env(@key, :string, "fallback") == "fallback"
        assert Config.get_env(@key, :integer, 99) == 99
        assert Config.get_env(@key, :boolean, true) == true
        assert Config.get_env(@key, :list, ["x"]) == ["x"]
      end)
    end

    test "parses the value when var is set (default ignored)" do
      with_env("real", fn -> assert Config.get_env(@key, :string, "fallback") == "real" end)
      with_env("100", fn -> assert Config.get_env(@key, :integer, 99) == 100 end)
    end

    test "default for :integer rescues the otherwise-raising case" do
      # Pattern that runtime.exs uses: Config.get_env("FOO", :integer, 1234)
      # for an optional integer-typed var.
      with_env(nil, fn -> assert Config.get_env(@key, :integer, 1234) == 1234 end)
    end

    test "empty string is treated as 'set' and parsed" do
      # Documents actual behaviour: get_env/3 only falls back to default on
      # nil, not on empty string. An empty string flows through to parse_env
      # — which has its own per-type behaviour ("" → false for :boolean,
      # "" → [] for :list, etc.).
      with_env("", fn -> assert Config.get_env(@key, :boolean, true) == false end)
      with_env("", fn -> assert Config.get_env(@key, :list, ["fallback"]) == [] end)
    end
  end

  # ---------------------------------------------------------------------------
  # get_env!/1 and get_env!/2 — strict reads
  # ---------------------------------------------------------------------------

  describe "get_env!/1" do
    test "returns the string when set" do
      with_env("required", fn -> assert Config.get_env!(@key) == "required" end)
    end

    test "raises when unset" do
      with_env(nil, fn ->
        assert_raise System.EnvError, fn -> Config.get_env!(@key) end
      end)
    end
  end

  describe "get_env!/2" do
    test "parses the typed value when set" do
      with_env("42", fn -> assert Config.get_env!(@key, :integer) == 42 end)
      with_env("true", fn -> assert Config.get_env!(@key, :boolean) == true end)
    end

    test "raises when unset, regardless of type" do
      with_env(nil, fn ->
        assert_raise System.EnvError, fn -> Config.get_env!(@key, :integer) end
        assert_raise System.EnvError, fn -> Config.get_env!(@key, :boolean) end
      end)
    end
  end
end
