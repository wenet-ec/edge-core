defmodule EdgeAgent.VpnTest do
  use ExUnit.Case, async: false

  alias EdgeAgent.Vpn

  defp with_app_env(key, value, fun) do
    old = Application.get_env(:edge_agent, key)
    Application.put_env(:edge_agent, key, value)

    try do
      fun.()
    after
      if old == nil do
        Application.delete_env(:edge_agent, key)
      else
        Application.put_env(:edge_agent, key, old)
      end
    end
  end

  # -----------------------------------------------------------------------
  # extract_enrollment_token/1 — pure, no I/O
  # -----------------------------------------------------------------------

  describe "extract_enrollment_token/1 — standard patterns (no custom path)" do
    setup do
      Application.delete_env(:edge_agent, :public_enrollment_key_path)
      on_exit(fn -> Application.delete_env(:edge_agent, :public_enrollment_key_path) end)
    end

    # Pattern 1: {"data": {"token": "..."}} — Phoenix, Rails, Laravel
    test "extracts token from data.token (Phoenix/Rails/Laravel pattern)" do
      body = %{"data" => %{"token" => "TOKEN=abc123"}}
      assert {:ok, "TOKEN=abc123"} = Vpn.extract_enrollment_token(body)
    end

    # Pattern 2: {"token": "..."} — Django, Express, NestJS
    test "extracts token from top-level token key" do
      body = %{"token" => "TOKEN=django_token"}
      assert {:ok, "TOKEN=django_token"} = Vpn.extract_enrollment_token(body)
    end

    # Pattern 3: {"enrollment_token": "..."}
    test "extracts token from enrollment_token key" do
      body = %{"enrollment_token" => "TOKEN=enroll_token"}
      assert {:ok, "TOKEN=enroll_token"} = Vpn.extract_enrollment_token(body)
    end

    # Pattern 4: {"enrollment_key": "..."}
    test "extracts token from enrollment_key key" do
      body = %{"enrollment_key" => "TOKEN=enroll_key"}
      assert {:ok, "TOKEN=enroll_key"} = Vpn.extract_enrollment_token(body)
    end

    # Pattern 5: {"key": "..."}
    test "extracts token from key field" do
      body = %{"key" => "TOKEN=short_key"}
      assert {:ok, "TOKEN=short_key"} = Vpn.extract_enrollment_token(body)
    end

    # Pattern 6: {"result": {"token": "..."}}
    test "extracts token from result.token" do
      body = %{"result" => %{"token" => "TOKEN=result_token"}}
      assert {:ok, "TOKEN=result_token"} = Vpn.extract_enrollment_token(body)
    end

    # Pattern 7: {"result": {"data": {"token": "..."}}}
    test "extracts token from result.data.token (deep nesting)" do
      body = %{"result" => %{"data" => %{"token" => "TOKEN=deep_token"}}}
      assert {:ok, "TOKEN=deep_token"} = Vpn.extract_enrollment_token(body)
    end

    # Pattern 8: {"data": {"enrollment_key": "..."}}
    test "extracts token from data.enrollment_key" do
      body = %{"data" => %{"enrollment_key" => "TOKEN=data_enroll"}}
      assert {:ok, "TOKEN=data_enroll"} = Vpn.extract_enrollment_token(body)
    end

    # Pattern 9: {"response": {"token": "..."}}
    test "extracts token from response.token" do
      body = %{"response" => %{"token" => "TOKEN=response_token"}}
      assert {:ok, "TOKEN=response_token"} = Vpn.extract_enrollment_token(body)
    end

    # Pattern 10: {"payload": {"token": "..."}}
    test "extracts token from payload.token" do
      body = %{"payload" => %{"token" => "TOKEN=payload_token"}}
      assert {:ok, "TOKEN=payload_token"} = Vpn.extract_enrollment_token(body)
    end

    test "returns error when no matching pattern found" do
      body = %{"unknown_key" => %{"also_unknown" => "TOKEN=abc"}}
      assert {:error, reason} = Vpn.extract_enrollment_token(body)
      assert is_binary(reason)
    end

    test "empty string token is not matched (skipped as falsy)" do
      body = %{"token" => ""}
      assert {:error, _reason} = Vpn.extract_enrollment_token(body)
    end

    test "nil token value is not matched" do
      body = %{"token" => nil}
      assert {:error, _reason} = Vpn.extract_enrollment_token(body)
    end

    test "non-string token value is not matched" do
      body = %{"token" => 12_345}
      assert {:error, _reason} = Vpn.extract_enrollment_token(body)
    end

    test "data.token takes priority over top-level token" do
      body = %{"data" => %{"token" => "TOKEN=data_wins"}, "token" => "TOKEN=top_level"}
      assert {:ok, "TOKEN=data_wins"} = Vpn.extract_enrollment_token(body)
    end

    test "extra keys alongside token are ignored" do
      body = %{"data" => %{"token" => "TOKEN=abc", "key_type" => "custom", "expires" => "2026-01-01"}}
      assert {:ok, "TOKEN=abc"} = Vpn.extract_enrollment_token(body)
    end
  end

  describe "extract_enrollment_token/1 — custom path via config" do
    setup do
      on_exit(fn -> Application.delete_env(:edge_agent, :public_enrollment_key_path) end)
    end

    test "extracts token using single-level custom path" do
      with_app_env(:public_enrollment_key_path, "mytoken", fn ->
        body = %{"mytoken" => "TOKEN=custom_single"}
        assert {:ok, "TOKEN=custom_single"} = Vpn.extract_enrollment_token(body)
      end)
    end

    test "extracts token using dot-separated custom path" do
      with_app_env(:public_enrollment_key_path, "data.attributes.token", fn ->
        body = %{"data" => %{"attributes" => %{"token" => "TOKEN=deep_custom"}}}
        assert {:ok, "TOKEN=deep_custom"} = Vpn.extract_enrollment_token(body)
      end)
    end

    test "returns error when custom path not found" do
      with_app_env(:public_enrollment_key_path, "a.b.c", fn ->
        body = %{"data" => %{"token" => "TOKEN=wrong_path"}}
        assert {:error, reason} = Vpn.extract_enrollment_token(body)
        assert reason =~ "a.b.c"
      end)
    end

    test "returns error when custom path points to non-string value" do
      with_app_env(:public_enrollment_key_path, "data.token", fn ->
        body = %{"data" => %{"token" => 99_999}}
        assert {:error, reason} = Vpn.extract_enrollment_token(body)
        assert reason =~ "data.token"
      end)
    end

    test "empty custom path string falls through to standard patterns" do
      with_app_env(:public_enrollment_key_path, "", fn ->
        body = %{"token" => "TOKEN=fallback"}
        assert {:ok, "TOKEN=fallback"} = Vpn.extract_enrollment_token(body)
      end)
    end

    test "nil custom path falls through to standard patterns" do
      with_app_env(:public_enrollment_key_path, nil, fn ->
        body = %{"token" => "TOKEN=fallback"}
        assert {:ok, "TOKEN=fallback"} = Vpn.extract_enrollment_token(body)
      end)
    end
  end

  describe "extract_enrollment_token/1 — binary body" do
    test "plain string longer than 10 chars with no braces treated as token" do
      assert {:ok, token} = Vpn.extract_enrollment_token("TOKEN=abc123xyz")
      assert token == "TOKEN=abc123xyz"
    end

    test "plain string is trimmed" do
      assert {:ok, "TOKEN=trimmed"} = Vpn.extract_enrollment_token("  TOKEN=trimmed  ")
    end

    test "string containing '{' is rejected (looks like JSON)" do
      assert {:error, _} = Vpn.extract_enrollment_token(~s({"token": "abc"}))
    end

    test "string containing '<' is rejected (looks like HTML/XML)" do
      assert {:error, _} = Vpn.extract_enrollment_token("<html>not a token</html>")
    end

    test "short string (10 chars or fewer) is rejected" do
      assert {:error, _} = Vpn.extract_enrollment_token("short")
      assert {:error, _} = Vpn.extract_enrollment_token("1234567890")
    end
  end

  describe "extract_enrollment_token/1 — non-map, non-binary body" do
    test "integer body returns error" do
      assert {:error, _} = Vpn.extract_enrollment_token(42)
    end

    test "nil body returns error" do
      assert {:error, _} = Vpn.extract_enrollment_token(nil)
    end

    test "list body returns error" do
      assert {:error, _} = Vpn.extract_enrollment_token(["token", "abc"])
    end
  end

  # -----------------------------------------------------------------------
  # get_enrollment_key/0 — App env injection, no HTTP
  # -----------------------------------------------------------------------

  describe "get_enrollment_key/0" do
    setup do
      on_exit(fn ->
        Application.delete_env(:edge_agent, :enrollment_key)
        Application.delete_env(:edge_agent, :public_enrollment_key_url)
      end)
    end

    test "returns explicit enrollment_key when configured" do
      Application.put_env(:edge_agent, :enrollment_key, "TOKEN=explicit_key")
      Application.delete_env(:edge_agent, :public_enrollment_key_url)

      assert {:ok, "TOKEN=explicit_key"} = Vpn.get_enrollment_key()
    end

    test "explicit enrollment_key takes priority over public URL" do
      Application.put_env(:edge_agent, :enrollment_key, "TOKEN=explicit_wins")
      Application.put_env(:edge_agent, :public_enrollment_key_url, "http://example.com/key")

      # Should use explicit key without making any HTTP call
      assert {:ok, "TOKEN=explicit_wins"} = Vpn.get_enrollment_key()
    end

    test "empty enrollment_key falls through (not used)" do
      Application.put_env(:edge_agent, :enrollment_key, "")
      Application.delete_env(:edge_agent, :public_enrollment_key_url)

      assert {:error, reason} = Vpn.get_enrollment_key()
      assert reason =~ "No enrollment key configured"
    end

    test "nil enrollment_key falls through" do
      Application.put_env(:edge_agent, :enrollment_key, nil)
      Application.delete_env(:edge_agent, :public_enrollment_key_url)

      assert {:error, reason} = Vpn.get_enrollment_key()
      assert reason =~ "No enrollment key configured"
    end

    test "returns error when neither key nor url is configured" do
      Application.delete_env(:edge_agent, :enrollment_key)
      Application.delete_env(:edge_agent, :public_enrollment_key_url)

      assert {:error, reason} = Vpn.get_enrollment_key()
      assert reason =~ "No enrollment key configured"
      assert reason =~ "ENROLLMENT_KEY"
      assert reason =~ "PUBLIC_ENROLLMENT_KEY_URL"
    end

    test "empty public URL falls through to error (not treated as configured)" do
      Application.delete_env(:edge_agent, :enrollment_key)
      Application.put_env(:edge_agent, :public_enrollment_key_url, "")

      assert {:error, reason} = Vpn.get_enrollment_key()
      assert reason =~ "No enrollment key configured"
    end
  end
end
