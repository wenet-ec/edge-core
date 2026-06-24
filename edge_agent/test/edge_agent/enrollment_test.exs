# edge_agent/test/edge_agent/enrollment_test.exs
defmodule EdgeAgent.EnrollmentTest do
  use EdgeAgent.DataCase, async: false

  alias EdgeAgent.Enrollment
  alias EdgeAgent.Settings

  # Build a valid base64 enrollment key blob (mirrors admin's create_enrollment_key)
  defp build_blob(admin_urls, nonce \\ "abc123nonce") do
    %{"admin_urls" => admin_urls, "nonce" => nonce}
    |> JSON.encode!()
    |> Base.encode64(padding: false)
  end

  # -----------------------------------------------------------------------
  # ensure_verified/0 — short-circuit when enrollment_verified=true in Settings
  # -----------------------------------------------------------------------

  describe "ensure_verified/0 — already verified (idempotent short-circuit)" do
    test "returns :ok immediately when enrollment_verified is true in Settings" do
      Settings.set_enrollment_verified(true)
      assert :ok = Enrollment.ensure_verified()
    end

    test "does not attempt to contact admin when already verified" do
      # No enrollment_key configured AND no admin URL — if it tried to verify,
      # it would fail. The short-circuit must fire first.
      Application.delete_env(:edge_agent, :enrollment_key)
      Application.delete_env(:edge_agent, :public_enrollment_key_urls)
      Settings.set_enrollment_verified(true)

      assert :ok = Enrollment.ensure_verified()
    after
      Application.delete_env(:edge_agent, :enrollment_key)
      Application.delete_env(:edge_agent, :public_enrollment_key_urls)
    end
  end

  describe "ensure_verified/0 — not yet verified, missing key" do
    setup do
      Settings.set_enrollment_verified(false)

      on_exit(fn ->
        Application.delete_env(:edge_agent, :enrollment_key)
        Application.delete_env(:edge_agent, :public_enrollment_key_urls)
      end)
    end

    test "returns error when no enrollment key configured" do
      Application.delete_env(:edge_agent, :enrollment_key)
      Application.delete_env(:edge_agent, :public_enrollment_key_urls)

      assert {:error, reason} = Enrollment.ensure_verified()
      assert is_binary(reason)
      assert reason =~ "ENROLLMENT_KEY"
    end

    test "returns error when enrollment key is empty string" do
      Application.put_env(:edge_agent, :enrollment_key, "")
      Application.delete_env(:edge_agent, :public_enrollment_key_urls)

      assert {:error, reason} = Enrollment.ensure_verified()
      assert is_binary(reason)
    end

    test "returns error when enrollment key is not valid base64" do
      Application.put_env(:edge_agent, :enrollment_key, "not-base64!!!")
      Application.delete_env(:edge_agent, :public_enrollment_key_urls)

      assert {:error, reason} = Enrollment.ensure_verified()
      assert reason =~ "base64"
    end

    test "returns error when enrollment key base64 decodes to non-JSON" do
      bad = Base.encode64("this is not json", padding: false)
      Application.put_env(:edge_agent, :enrollment_key, bad)
      Application.delete_env(:edge_agent, :public_enrollment_key_urls)

      assert {:error, reason} = Enrollment.ensure_verified()
      assert reason =~ "JSON"
    end

    test "returns error when enrollment key JSON is missing admin_urls" do
      blob = %{"nonce" => "abc"} |> JSON.encode!() |> Base.encode64(padding: false)
      Application.put_env(:edge_agent, :enrollment_key, blob)
      Application.delete_env(:edge_agent, :public_enrollment_key_urls)

      assert {:error, reason} = Enrollment.ensure_verified()
      assert reason =~ "admin_urls"
    end

    test "returns error when admin_urls is an empty list" do
      blob = build_blob([])
      Application.put_env(:edge_agent, :enrollment_key, blob)
      Application.delete_env(:edge_agent, :public_enrollment_key_urls)

      assert {:error, reason} = Enrollment.ensure_verified()
      assert is_binary(reason)
    end

    test "returns error when admin is unreachable (verify request fails)" do
      # Valid blob with a real admin_urls list — decoding succeeds,
      # but admin at 127.0.0.1:1 is not running → verify fails
      blob = build_blob(["http://127.0.0.1:1"])
      Application.put_env(:edge_agent, :enrollment_key, blob)
      Application.delete_env(:edge_agent, :public_enrollment_key_urls)

      assert {:error, reason} = Enrollment.ensure_verified()
      assert is_binary(reason)
    end

    test "enrollment_verified remains false after a failed verify" do
      Application.delete_env(:edge_agent, :enrollment_key)
      Application.delete_env(:edge_agent, :public_enrollment_key_urls)

      Enrollment.ensure_verified()
      refute Settings.get_enrollment_verified()
    end

    test "returns error when public_enrollment_key_urls is set to empty list" do
      Application.delete_env(:edge_agent, :enrollment_key)
      Application.put_env(:edge_agent, :public_enrollment_key_urls, [])

      assert {:error, reason} = Enrollment.ensure_verified()
      assert reason =~ "ENROLLMENT_KEY"
    end

    test "tries all URLs when each one is unreachable" do
      # All URLs unreachable → final error mentions transport failure, not
      # "no key configured" (proves the list was iterated, not skipped).
      Application.delete_env(:edge_agent, :enrollment_key)

      Application.put_env(:edge_agent, :public_enrollment_key_urls, [
        "http://127.0.0.1:1/enroll",
        "http://127.0.0.1:2/enroll"
      ])

      assert {:error, reason} = Enrollment.ensure_verified()
      assert reason =~ "All enrollment key URLs failed"
    end
  end

  # -----------------------------------------------------------------------
  # extract_from_response/1 — response-body extraction contract
  #
  # Promoted to def @doc false for testability per TESTING.md. The
  # critical contract is the prepend-not-override semantics of
  # PUBLIC_ENROLLMENT_KEY_PATHS: when none of the custom paths match a given
  # body, the built-in patterns must still get a fair shot. Otherwise a
  # multi-URL setup mixing edge-admin + third-party would silently break.
  # -----------------------------------------------------------------------

  describe "extract_from_response/1 — custom PATH semantics" do
    setup do
      on_exit(fn ->
        Application.delete_env(:edge_agent, :public_enrollment_key_paths)
      end)
    end

    test "custom path matches when body has the configured shape" do
      Application.put_env(:edge_agent, :public_enrollment_key_paths, ["auth.token"])
      body = %{"auth" => %{"token" => "k-from-custom-path"}}

      assert {:ok, "k-from-custom-path"} = Enrollment.extract_from_response(body)
    end

    test "falls through to built-in patterns when custom path misses (mixed-source case)" do
      # This is the contract that makes multi-URL with mixed sources safe:
      # PATH is set for a third-party URL, but the standard edge-admin URL
      # in the same list still returns its usual {data: {key: ...}} shape.
      # The fallback must still match it.
      Application.put_env(:edge_agent, :public_enrollment_key_paths, ["auth.token"])
      body = %{"data" => %{"key" => "k-from-builtin"}}

      assert {:ok, "k-from-builtin"} = Enrollment.extract_from_response(body)
    end

    test "custom path wins over built-in when both could match" do
      # Body has both auth.token AND data.key. PATH should take precedence.
      Application.put_env(:edge_agent, :public_enrollment_key_paths, ["auth.token"])
      body = %{"auth" => %{"token" => "from-path"}, "data" => %{"key" => "from-builtin"}}

      assert {:ok, "from-path"} = Enrollment.extract_from_response(body)
    end

    test "tries each path in order, returns first match" do
      Application.put_env(:edge_agent, :public_enrollment_key_paths, ["auth.token", "data.key"])
      body = %{"data" => %{"key" => "from-second"}}

      assert {:ok, "from-second"} = Enrollment.extract_from_response(body)
    end

    test "first matching path wins when multiple paths match" do
      Application.put_env(:edge_agent, :public_enrollment_key_paths, ["auth.token", "data.key"])
      body = %{"auth" => %{"token" => "from-first"}, "data" => %{"key" => "from-second"}}

      assert {:ok, "from-first"} = Enrollment.extract_from_response(body)
    end

    test "empty list falls through to built-ins" do
      Application.put_env(:edge_agent, :public_enrollment_key_paths, [])
      body = %{"data" => %{"key" => "k-fallback"}}

      assert {:ok, "k-fallback"} = Enrollment.extract_from_response(body)
    end

    test "returns error when neither paths nor built-ins match" do
      Application.put_env(:edge_agent, :public_enrollment_key_paths, ["auth.token"])
      body = %{"unrelated" => "value"}

      assert {:error, reason} = Enrollment.extract_from_response(body)
      assert reason =~ "Could not extract"
    end
  end

  describe "extract_from_response/1 — built-in patterns (PATH unset)" do
    setup do
      Application.delete_env(:edge_agent, :public_enrollment_key_paths)
      :ok
    end

    test "matches the standard edge-admin envelope: data.key" do
      assert {:ok, "k1"} = Enrollment.extract_from_response(%{"data" => %{"key" => "k1"}})
    end

    test "matches top-level key" do
      assert {:ok, "k2"} = Enrollment.extract_from_response(%{"key" => "k2"})
    end

    test "matches top-level enrollment_key" do
      assert {:ok, "k3"} = Enrollment.extract_from_response(%{"enrollment_key" => "k3"})
    end

    test "returns error when no pattern matches" do
      assert {:error, _} = Enrollment.extract_from_response(%{"random" => "value"})
    end

    test "ignores empty-string values in pattern matches" do
      # data.key is the first built-in pattern, but the value is empty —
      # extraction should fall through and ultimately fail rather than
      # returning {:ok, ""}.
      assert {:error, _} = Enrollment.extract_from_response(%{"data" => %{"key" => ""}})
    end
  end

  describe "extract_from_response/1 — non-map bodies" do
    test "accepts a plain-string body that looks like a key" do
      assert {:ok, "abcdefghij1234"} = Enrollment.extract_from_response("abcdefghij1234")
    end

    test "strips leading/trailing whitespace on string bodies" do
      assert {:ok, "abcdefghij1234"} = Enrollment.extract_from_response("  abcdefghij1234\n")
    end

    test "rejects a string body that looks like JSON or HTML" do
      assert {:error, _} = Enrollment.extract_from_response(~s({"key":"value"}))
      assert {:error, _} = Enrollment.extract_from_response("<html></html>")
    end

    test "rejects a too-short string body" do
      assert {:error, _} = Enrollment.extract_from_response("abc")
    end

    test "rejects non-map non-string bodies" do
      assert {:error, _} = Enrollment.extract_from_response(123)
      assert {:error, _} = Enrollment.extract_from_response(nil)
      assert {:error, _} = Enrollment.extract_from_response([])
    end
  end

  # -----------------------------------------------------------------------
  # enrollment key blob format — pure Base64+JSON decode, no module call
  # -----------------------------------------------------------------------

  describe "enrollment key blob format" do
    test "correctly formed blob decodes to admin_urls list" do
      urls = ["https://admin1.example.com", "https://admin2.example.com"]
      blob = build_blob(urls)

      assert {:ok, json} = Base.decode64(blob, padding: false)
      assert {:ok, decoded} = JSON.decode(json)
      assert decoded["admin_urls"] == urls
    end

    test "blob has no padding characters (padding: false)" do
      blob = build_blob(["https://admin.example.com"])
      refute String.ends_with?(blob, "=")
    end

    test "nonce field is present in blob" do
      blob = build_blob(["https://admin.example.com"], "my-nonce")
      {:ok, json} = Base.decode64(blob, padding: false)
      {:ok, decoded} = JSON.decode(json)
      assert decoded["nonce"] == "my-nonce"
    end

    test "nonce is ignored by the decode path — only admin_urls matters" do
      # Both blobs have same admin_urls but different nonces — both are valid
      blob1 = build_blob(["https://admin.example.com"], "nonce-1")
      blob2 = build_blob(["https://admin.example.com"], "nonce-2")
      assert blob1 != blob2

      {:ok, json1} = Base.decode64(blob1, padding: false)
      {:ok, json2} = Base.decode64(blob2, padding: false)
      {:ok, d1} = JSON.decode(json1)
      {:ok, d2} = JSON.decode(json2)
      assert d1["admin_urls"] == d2["admin_urls"]
    end
  end
end
