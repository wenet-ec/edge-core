# edge_agent/test/edge_agent/enrollment_test.exs
defmodule EdgeAgent.EnrollmentTest do
  use EdgeAgent.DataCase, async: false

  alias EdgeAgent.Enrollment
  alias EdgeAgent.Settings

  # Build a valid base64 enrollment key blob (mirrors admin's create_enrollment_key)
  defp build_blob(admin_urls, nonce \\ "abc123nonce") do
    %{"admin_urls" => admin_urls, "nonce" => nonce}
    |> Jason.encode!()
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
      Application.delete_env(:edge_agent, :public_enrollment_key_url)
      Settings.set_enrollment_verified(true)

      assert :ok = Enrollment.ensure_verified()
    after
      Application.delete_env(:edge_agent, :enrollment_key)
      Application.delete_env(:edge_agent, :public_enrollment_key_url)
    end
  end

  describe "ensure_verified/0 — not yet verified, missing key" do
    setup do
      Settings.set_enrollment_verified(false)

      on_exit(fn ->
        Application.delete_env(:edge_agent, :enrollment_key)
        Application.delete_env(:edge_agent, :public_enrollment_key_url)
      end)
    end

    test "returns error when no enrollment key configured" do
      Application.delete_env(:edge_agent, :enrollment_key)
      Application.delete_env(:edge_agent, :public_enrollment_key_url)

      assert {:error, reason} = Enrollment.ensure_verified()
      assert is_binary(reason)
      assert reason =~ "ENROLLMENT_KEY"
    end

    test "returns error when enrollment key is empty string" do
      Application.put_env(:edge_agent, :enrollment_key, "")
      Application.delete_env(:edge_agent, :public_enrollment_key_url)

      assert {:error, reason} = Enrollment.ensure_verified()
      assert is_binary(reason)
    end

    test "returns error when enrollment key is not valid base64" do
      Application.put_env(:edge_agent, :enrollment_key, "not-base64!!!")
      Application.delete_env(:edge_agent, :public_enrollment_key_url)

      assert {:error, reason} = Enrollment.ensure_verified()
      assert reason =~ "base64"
    end

    test "returns error when enrollment key base64 decodes to non-JSON" do
      bad = Base.encode64("this is not json", padding: false)
      Application.put_env(:edge_agent, :enrollment_key, bad)
      Application.delete_env(:edge_agent, :public_enrollment_key_url)

      assert {:error, reason} = Enrollment.ensure_verified()
      assert reason =~ "JSON"
    end

    test "returns error when enrollment key JSON is missing admin_urls" do
      blob = %{"nonce" => "abc"} |> Jason.encode!() |> Base.encode64(padding: false)
      Application.put_env(:edge_agent, :enrollment_key, blob)
      Application.delete_env(:edge_agent, :public_enrollment_key_url)

      assert {:error, reason} = Enrollment.ensure_verified()
      assert reason =~ "admin_urls"
    end

    test "returns error when admin_urls is an empty list" do
      blob = build_blob([])
      Application.put_env(:edge_agent, :enrollment_key, blob)
      Application.delete_env(:edge_agent, :public_enrollment_key_url)

      assert {:error, reason} = Enrollment.ensure_verified()
      assert is_binary(reason)
    end

    test "returns error when admin is unreachable (verify request fails)" do
      # Valid blob with a real admin_urls list — decoding succeeds,
      # but admin at 127.0.0.1:1 is not running → verify fails
      blob = build_blob(["http://127.0.0.1:1"])
      Application.put_env(:edge_agent, :enrollment_key, blob)
      Application.delete_env(:edge_agent, :public_enrollment_key_url)

      assert {:error, reason} = Enrollment.ensure_verified()
      assert is_binary(reason)
    end

    test "enrollment_verified remains false after a failed verify" do
      Application.delete_env(:edge_agent, :enrollment_key)
      Application.delete_env(:edge_agent, :public_enrollment_key_url)

      Enrollment.ensure_verified()
      refute Settings.get_enrollment_verified()
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
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["admin_urls"] == urls
    end

    test "blob has no padding characters (padding: false)" do
      blob = build_blob(["https://admin.example.com"])
      refute String.ends_with?(blob, "=")
    end

    test "nonce field is present in blob" do
      blob = build_blob(["https://admin.example.com"], "my-nonce")
      {:ok, json} = Base.decode64(blob, padding: false)
      {:ok, decoded} = Jason.decode(json)
      assert decoded["nonce"] == "my-nonce"
    end

    test "nonce is ignored by the decode path — only admin_urls matters" do
      # Both blobs have same admin_urls but different nonces — both are valid
      blob1 = build_blob(["https://admin.example.com"], "nonce-1")
      blob2 = build_blob(["https://admin.example.com"], "nonce-2")
      assert blob1 != blob2

      {:ok, json1} = Base.decode64(blob1, padding: false)
      {:ok, json2} = Base.decode64(blob2, padding: false)
      {:ok, d1} = Jason.decode(json1)
      {:ok, d2} = Jason.decode(json2)
      assert d1["admin_urls"] == d2["admin_urls"]
    end
  end
end
