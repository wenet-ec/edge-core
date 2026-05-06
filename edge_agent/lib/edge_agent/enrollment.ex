# edge_agent/lib/edge_agent/enrollment.ex
defmodule EdgeAgent.Enrollment do
  @moduledoc """
  Handles admin enrollment key verification for the edge agent.

  The enrollment key is a base64-encoded JSON blob issued by admin:

      base64({"admin_urls": ["https://admin.example.com"], "nonce": "<random_32_bytes_base64>"})

  It can be provided directly via `ENROLLMENT_KEY` or fetched from
  `PUBLIC_ENROLLMENT_KEY_URL` (same format, returned by the admin's public
  enrollment endpoint).

  ## Flow

      ensure_verified()
        ├── enrollment_verified=true in Settings? → :ok (skip)
        └── not verified:
              1. Get enrollment key (ENROLLMENT_KEY env, or fetch from PUBLIC_ENROLLMENT_KEY_URL)
              2. Decode → extract admin_urls (nonce is ignored — it only makes the blob unique)
              3. POST the full key blob to admin verify endpoint
              4. On success: store admin_fallback_urls, netmaker_key,
                 enrollment_verified=true to Settings
              5. Return :ok

  ## Crash Safety

  Settings writes are ordered so `enrollment_verified=true` is the last one.
  If the agent crashes after `ensure_verified/0` returns `:ok`, the next
  bootstrap sees the verified flag and skips re-verification, preserving
  the enrollment key's use count.

  A crash *during* the write sequence — between the
  `set_admin_fallback_urls/1` / `set_netmaker_key/1` writes and the final
  `set_enrollment_verified(true)` — leaves the verified flag false. The
  next bootstrap will re-verify and consume another key use. Limited-use
  keys with very narrow crash windows could deplete this way, but in
  practice the writes are SQLite upserts and complete in microseconds.

  ## Configuration

  - `ENROLLMENT_KEY` — base64 enrollment key (highest priority)
  - `PUBLIC_ENROLLMENT_KEY_URL` — URL to POST to receive the enrollment key (fallback)
  - `PUBLIC_ENROLLMENT_KEY_PATH` — custom JSON path for extraction from URL response
  """

  alias EdgeAgent.EdgeClusters.AdminClient
  alias EdgeAgent.Settings

  require Logger

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Ensures the agent has a verified enrollment key.

  Idempotent — if `enrollment_verified=true` is already in Settings, returns
  immediately without contacting admin or consuming a key use.

  On success, Settings will contain:
  - `enrollment_verified` = true
  - `netmaker_key` — for use by `EdgeAgent.Vpn`
  - `admin_fallback_urls` — for use by `AdminClient` when VPN is down
  """
  @spec ensure_verified() :: :ok | {:error, String.t()}
  def ensure_verified do
    if Settings.get_enrollment_verified() do
      Logger.info("Enrollment already verified, skipping")
      :ok
    else
      do_verify()
    end
  end

  # =============================================================================
  # Private — Verification Flow
  # =============================================================================

  defp do_verify do
    with {:ok, enrollment_key} <- get_enrollment_key(),
         {:ok, admin_urls} <- decode(enrollment_key),
         {:ok, netmaker_key} <- verify_with_admin(enrollment_key, admin_urls) do
      Settings.set_admin_fallback_urls(admin_urls)
      Settings.set_netmaker_key(netmaker_key)
      Settings.set_enrollment_verified(true)
      :ok
    end
  end

  # =============================================================================
  # Private — Get Enrollment Key
  # =============================================================================

  defp get_enrollment_key do
    enrollment_key = Application.get_env(:edge_agent, :enrollment_key)
    public_key_url = Application.get_env(:edge_agent, :public_enrollment_key_url)

    cond do
      is_binary(enrollment_key) and enrollment_key != "" ->
        Logger.info("Using ENROLLMENT_KEY from configuration")
        {:ok, enrollment_key}

      is_binary(public_key_url) and public_key_url != "" ->
        Logger.info("Fetching enrollment key from: #{public_key_url}")
        fetch_from_url(public_key_url)

      true ->
        {:error, "No enrollment key configured (set ENROLLMENT_KEY or PUBLIC_ENROLLMENT_KEY_URL)"}
    end
  end

  defp fetch_from_url(url) do
    timeout = Application.get_env(:edge_agent, :admin_call_timeout, 10_000)

    opts = [
      receive_timeout: timeout,
      connect_options: [timeout: timeout],
      retry: false
    ]

    case Req.post(url, opts) do
      {:ok, %{status: status, body: body}} when status in [200, 201] ->
        extract_from_response(body)

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to fetch enrollment key: HTTP #{status}, body: #{inspect(body)}")
        {:error, "Public enrollment key request failed: HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Failed to fetch enrollment key: #{inspect(reason)}")
        {:error, "Failed to fetch enrollment key: #{inspect(reason)}"}
    end
  end

  defp extract_from_response(body) when is_map(body) do
    custom_path = Application.get_env(:edge_agent, :public_enrollment_key_path)

    result =
      if is_binary(custom_path) and custom_path != "" do
        get_in_path(body, String.split(custom_path, "."))
      else
        try_extraction_patterns(body)
      end

    case result do
      key when is_binary(key) and key != "" ->
        {:ok, key}

      _ ->
        Logger.error("Could not extract enrollment key from response: #{inspect(body)}")
        {:error, "Could not extract enrollment key from response"}
    end
  end

  defp extract_from_response(body) when is_binary(body) do
    trimmed = String.trim(body)

    if String.length(trimmed) > 10 and not String.contains?(trimmed, ["{", "<"]) do
      {:ok, trimmed}
    else
      {:error, "Response body does not look like an enrollment key"}
    end
  end

  defp extract_from_response(_), do: {:error, "Response body is not a map or string"}

  defp try_extraction_patterns(body) do
    patterns = [
      fn -> get_in(body, ["data", "key"]) end,
      fn -> get_in(body, ["data", "token"]) end,
      fn -> Map.get(body, "key") end,
      fn -> Map.get(body, "token") end,
      fn -> Map.get(body, "enrollment_token") end,
      fn -> Map.get(body, "enrollment_key") end,
      fn -> get_in(body, ["result", "key"]) end,
      fn -> get_in(body, ["result", "token"]) end,
      fn -> get_in(body, ["result", "data", "key"]) end,
      fn -> get_in(body, ["result", "data", "token"]) end,
      fn -> get_in(body, ["data", "enrollment_key"]) end,
      fn -> get_in(body, ["response", "token"]) end,
      fn -> get_in(body, ["payload", "token"]) end
    ]

    Enum.find_value(patterns, fn f ->
      case f.() do
        v when is_binary(v) and v != "" -> v
        _ -> nil
      end
    end)
  end

  defp get_in_path(val, []), do: val
  defp get_in_path(map, [key | rest]) when is_map(map), do: get_in_path(Map.get(map, key), rest)
  defp get_in_path(_, _), do: nil

  # =============================================================================
  # Private — Decode
  # =============================================================================

  defp decode(enrollment_key) do
    with {:ok, json} <- Base.decode64(enrollment_key, padding: false),
         {:ok, decoded} <- Jason.decode(json),
         admin_urls when is_list(admin_urls) and admin_urls != [] <- Map.get(decoded, "admin_urls") do
      {:ok, admin_urls}
    else
      :error -> {:error, "ENROLLMENT_KEY is not valid base64"}
      {:error, _} -> {:error, "ENROLLMENT_KEY is not valid JSON"}
      _ -> {:error, "ENROLLMENT_KEY is missing admin_urls field"}
    end
  end

  # =============================================================================
  # Private — Verify with Admin
  # =============================================================================

  defp verify_with_admin(key_blob, admin_urls) do
    case AdminClient.verify_enrollment_key(key_blob, admin_urls) do
      {:ok, %{verified: true, netmaker_key: netmaker_key}} ->
        Logger.info("Enrollment key verified successfully")
        {:ok, netmaker_key}

      {:ok, %{verified: false, error: error}} ->
        Logger.error("Enrollment key rejected by admin: #{error}")
        {:error, "Enrollment key verification failed: #{error}"}

      {:error, reason} ->
        Logger.error("Could not reach admin for enrollment verification: #{inspect(reason)}")
        {:error, "Enrollment key verification request failed: #{inspect(reason)}"}
    end
  end
end
