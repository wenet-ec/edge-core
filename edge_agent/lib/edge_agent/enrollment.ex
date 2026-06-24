# edge_agent/lib/edge_agent/enrollment.ex
defmodule EdgeAgent.Enrollment do
  @moduledoc """
  Handles admin enrollment key verification for the edge agent.

  The enrollment key is a base64-encoded JSON blob issued by admin:

      base64({"admin_urls": ["https://admin.example.com"], "nonce": "<random_32_bytes_base64>"})

  It can be provided directly via `ENROLLMENT_KEY` or fetched from one of
  the URLs in `PUBLIC_ENROLLMENT_KEY_URLS` (comma-separated, tried in order).
  Any admin can mint a key — admins share the same Postgres — so the list
  is a pure availability fallback, not a routing decision.

  ## Flow

      ensure_verified()
        ├── enrollment_verified=true in Settings? → :ok (skip)
        └── not verified:
              1. Get enrollment key (ENROLLMENT_KEY env, or fetch by trying
                 PUBLIC_ENROLLMENT_KEY_URLS in order until one succeeds)
              2. Decode → extract admin_urls (nonce is ignored — it only makes the blob unique)
              3. POST the full key blob to admin verify endpoint
              4. On success: store admin_fallback_urls, netmaker_key,
                 enrollment_verified=true to Settings
              5. Return :ok

  ## Multi-URL failover semantics

  Transport errors (timeout, connection refused, DNS failure) on URL N
  cause the agent to try URL N+1. HTTP errors (non-2xx response) are
  treated as terminal — they mean a reachable admin rejected the request,
  which is almost always a config bug (`PUBLIC_ENROLLMENT_KEY_ENABLED=false`,
  wrong cluster name, etc.) that another admin would reject identically.
  Failing over on those would hide the real problem.

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
  - `PUBLIC_ENROLLMENT_KEY_URLS` — comma-separated URLs to POST to receive
    the enrollment key (fallback; tried in order)
  - `PUBLIC_ENROLLMENT_KEY_PATH` — dotted JSON path for extracting the key
    from the response body (e.g. `data.key`, `result.token`,
    `payload.enrollment_key`). Tried *first*, then the built-in patterns
    fall through. Set this when integrating with a third-party admin whose
    response shape doesn't match any of the built-in patterns; the
    fall-through ensures other URLs in `PUBLIC_ENROLLMENT_KEY_URLS` with
    standard shapes still work.
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
    urls = Application.get_env(:edge_agent, :public_enrollment_key_urls, [])

    cond do
      is_binary(enrollment_key) and enrollment_key != "" ->
        Logger.info("Using ENROLLMENT_KEY from configuration")
        {:ok, enrollment_key}

      is_list(urls) and urls != [] ->
        fetch_from_urls(urls)

      true ->
        {:error, "No enrollment key configured (set ENROLLMENT_KEY or PUBLIC_ENROLLMENT_KEY_URLS)"}
    end
  end

  # Try each URL in order. Transport errors fall through to the next URL;
  # HTTP errors (non-2xx) and extraction failures are terminal — see
  # moduledoc for rationale.
  defp fetch_from_urls(urls) do
    Enum.reduce_while(urls, {:error, "No URLs to try"}, fn url, _acc ->
      Logger.info("Fetching enrollment key from: #{url}")

      case fetch_from_url(url) do
        {:ok, key} ->
          {:halt, {:ok, key}}

        {:transport_error, reason} ->
          Logger.warning("Transport error fetching enrollment key from #{url}: #{inspect(reason)} — trying next URL")

          {:cont, {:error, "All enrollment key URLs failed: last error #{inspect(reason)}"}}

        {:error, _reason} = terminal ->
          {:halt, terminal}
      end
    end)
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
        Logger.error("Failed to fetch enrollment key from #{url}: HTTP #{status}, body: #{inspect(body)}")
        {:error, "Public enrollment key request failed: HTTP #{status}"}

      {:error, reason} ->
        {:transport_error, reason}
    end
  end

  @doc false
  # Promoted from defp for testability — pins the contract for the
  # response-body extraction step. See TESTING.md "Promote-to-public for
  # testability". Not part of the user-facing API.
  #
  # When `PUBLIC_ENROLLMENT_KEY_PATH` is set, the custom path is tried
  # *first*, then the built-in pattern list falls through. With multi-URL
  # configured, a single PATH meant for a third-party endpoint would
  # otherwise break extraction for sibling URLs returning a standard shape;
  # the prepend-not-override semantics let mixed sources coexist.
  @spec extract_from_response(map() | binary() | any()) :: {:ok, String.t()} | {:error, String.t()}
  def extract_from_response(body) when is_map(body) do
    custom_path = Application.get_env(:edge_agent, :public_enrollment_key_path)

    result =
      case try_custom_path(body, custom_path) do
        nil -> try_extraction_patterns(body)
        key -> key
      end

    case result do
      key when is_binary(key) and key != "" ->
        {:ok, key}

      _ ->
        Logger.error("Could not extract enrollment key from response: #{inspect(body)}")
        {:error, "Could not extract enrollment key from response"}
    end
  end

  def extract_from_response(body) when is_binary(body) do
    trimmed = String.trim(body)

    if String.length(trimmed) > 10 and not String.contains?(trimmed, ["{", "<"]) do
      {:ok, trimmed}
    else
      {:error, "Response body does not look like an enrollment key"}
    end
  end

  def extract_from_response(_), do: {:error, "Response body is not a map or string"}

  defp try_custom_path(_body, path) when path in [nil, ""], do: nil
  defp try_custom_path(body, path), do: get_in_path(body, String.split(path, "."))

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
         {:ok, decoded} <- JSON.decode(json),
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
