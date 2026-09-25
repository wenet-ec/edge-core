# edge_agent/test/edge_agent/enrollment_test.exs
defmodule EdgeAgent.EnrollmentTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.Enrollment

  describe "extract_from_response/2" do
    test "custom path takes precedence over built-in patterns" do
      body = %{"auth" => %{"token" => "custom"}, "data" => %{"key" => "builtin"}}
      assert {:ok, "custom"} = Enrollment.extract_from_response(body, ["auth.token"])
    end

    test "falls through to built-in patterns when custom path misses" do
      body = %{"data" => %{"key" => "builtin"}}
      assert {:ok, "builtin"} = Enrollment.extract_from_response(body, ["auth.token"])
    end

    test "tries custom paths in order" do
      body = %{"auth" => %{"token" => "first"}, "data" => %{"key" => "second"}}
      assert {:ok, "first"} = Enrollment.extract_from_response(body, ["auth.token", "data.key"])
    end

    test "returns an error when no object pattern matches" do
      assert {:error, _} = Enrollment.extract_from_response(%{"other" => "value"}, [])
    end

    test "accepts a plain key string and trims surrounding whitespace" do
      assert {:ok, "abcdefghij1234"} = Enrollment.extract_from_response("  abcdefghij1234\n", [])
    end

    test "rejects short, JSON-looking, and HTML-looking strings" do
      for body <- ["abc", ~s({"key":"value"}), "<html></html>"] do
        assert {:error, _} = Enrollment.extract_from_response(body, [])
      end
    end

    test "rejects unsupported body types" do
      assert {:error, _} = Enrollment.extract_from_response([], [])
    end
  end

  describe "verify_recovery_key/2" do
    test "accepts no recovery key for ordinary enrollment" do
      assert :ok = Enrollment.verify_recovery_key(nil, "production")
      assert :ok = Enrollment.verify_recovery_key("", "production")
    end

    test "requires a valid matching cluster recovery blob" do
      recovery_key =
        %{
          "node_id" => "123e4567-e89b-12d3-a456-426614174000",
          "nonce" => "nonce",
          "cluster_name" => "production"
        }
        |> JSON.encode!()
        |> Base.encode64()

      assert :ok = Enrollment.verify_recovery_key(recovery_key, "production")
      assert {:error, _} = Enrollment.verify_recovery_key(recovery_key, "staging")
      assert {:error, _} = Enrollment.verify_recovery_key("not-base64", "production")
    end
  end
end
