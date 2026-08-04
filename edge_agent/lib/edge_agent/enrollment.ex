# edge_agent/lib/edge_agent/enrollment.ex
defmodule EdgeAgent.Enrollment do
  @moduledoc """
  Handles admin enrollment key verification for the edge agent.

  The enrollment key is a base64-encoded JSON blob issued by admin:

      base64({"admin_urls": ["https://admin.example.com"], "cluster_name": "production", "nonce": "<random_32_bytes_base64>"})

  It can be provided directly via `ENROLLMENT_KEY` or fetched from one of
  the URLs in `PUBLIC_ENROLLMENT_KEY_URLS` (comma-separated, tried in order).
  Any admin can mint a key — admins share the same Postgres — so the list
  is a pure availability fallback, not a routing decision.

  ## Flow

      ensure_verified(recovery_key)
        ├── enrollment_key_id is present and no recovery key? → :ok (skip)
        └── enrollment_key_id is absent:
              1. Get enrollment key (ENROLLMENT_KEY env, or fetch by trying
                 PUBLIC_ENROLLMENT_KEY_URLS in order until one succeeds)
              2. Decode → extract admin_urls and cluster_name (nonce only makes the blob unique)
              3. If recovering, verify the recovery key belongs to cluster_name
              4. POST the full key blob to admin verify endpoint
              5. Require a non-empty Netmaker enrollment key
              6. On success: store admin_fallback_urls, netmaker_key,
                 then write enrollment_key_id last as the durable commit marker

  ## Multi-URL failover semantics

  Transport errors (timeout, connection refused, DNS failure) on URL N
  cause the agent to try URL N+1. HTTP errors (non-2xx response) are
  treated as terminal — they mean a reachable admin rejected the request,
  which is almost always a config bug (`PUBLIC_ENROLLMENT_KEY_ENABLED=false`,
  wrong cluster name, etc.) that another admin would reject identically.
  Failing over on those would hide the real problem.

  ## Crash Safety

  Settings writes are ordered so `enrollment_key_id` is the last one.
  If the agent crashes after `ensure_verified/0` returns `:ok`, the next
  bootstrap sees the key ID and skips re-verification, preserving
  the enrollment key's use count.

  A crash *during* the write sequence — between the
  `set_admin_fallback_urls/1` / `set_netmaker_key/1` writes and the final
  `set_enrollment_key_id/1` — leaves the key ID absent. The
  next bootstrap will re-verify and consume another key use. Limited-use
  keys with very narrow crash windows could deplete this way, but in
  practice the writes are SQLite upserts and complete in microseconds.

  ## Configuration

  - `ENROLLMENT_KEY` — base64 enrollment key (highest priority)
  - `PUBLIC_ENROLLMENT_KEY_URLS` — comma-separated URLs to POST to receive
    the enrollment key (fallback; tried in order)
  - `PUBLIC_ENROLLMENT_KEY_PATHS` — comma-separated list of dotted JSON paths
    for extracting the key from the response body (e.g.
    `data.key,result.token,payload.enrollment_key`). Each path is tried in
    order *first*, then the built-in patterns fall through. Set this when
    integrating with a third-party admin whose response shape doesn't match
    any of the built-in patterns; the fall-through ensures other URLs in
    `PUBLIC_ENROLLMENT_KEY_URLS` with standard shapes still work.
  """

  alias EdgeAgent.EdgeClusters.AdminClient
  alias EdgeAgent.Settings

  require Logger

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Ensures the agent has a verified enrollment key.

  Idempotent — if `enrollment_key_id` is already in Settings, returns
  immediately without contacting admin or consuming a key use.

  On success, Settings will contain:
  - `netmaker_key` — for use by `EdgeAgent.Vpn`
  - `enrollment_key_id` — for associating the successful registration with Admin
  - `admin_fallback_urls` — for use by `AdminClient` when VPN is down
  """
  @spec ensure_verified() :: :ok | {:error, String.t()}
  def ensure_verified, do: ensure_verified(nil)

  @spec ensure_verified(String.t() | nil) :: :ok | {:error, String.t()}
  def ensure_verified(recovery_key) do
    if enrollment_key_id_present?() do
      if recovery_key in [nil, ""] do
        Logger.info("Enrollment already verified, skipping")
        :ok
      else
        {:error, "Cannot use a recovery key after enrollment is already verified"}
      end
    else
      verify_and_persist(recovery_key)
    end
  end

  # =============================================================================
  # Private — Verification Flow
  # =============================================================================

  defp verify_and_persist(recovery_key) do
    with {:ok, enrollment_key} <- load_enrollment_key(),
         {:ok, %{admin_urls: admin_urls, cluster_name: cluster_name}} <-
           decode_enrollment_key(enrollment_key),
         :ok <- verify_recovery_key(recovery_key, cluster_name),
         {:ok, verification} <- verify_enrollment_key_with_admin(enrollment_key, admin_urls) do
      persist_enrollment_settings(admin_urls, verification)
    end
  end

  defp persist_enrollment_settings(admin_urls, %{netmaker_key: netmaker_key, enrollment_key_id: enrollment_key_id}) do
    with {:ok, _setting} <- Settings.set_admin_fallback_urls(admin_urls),
         {:ok, _setting} <- Settings.set_netmaker_key(netmaker_key),
         {:ok, _setting} <- Settings.set_enrollment_key_id(enrollment_key_id) do
      :ok
    else
      {:error, reason} ->
        {:error, "Failed to persist enrollment settings: #{inspect(reason)}"}
    end
  end

  defp enrollment_key_id_present? do
    case Settings.get_enrollment_key_id() do
      id when is_binary(id) and id != "" -> true
      _ -> false
    end
  end

  @doc """
  Verifies that a recovery key belongs to the enrollment cluster.

  A missing recovery key is valid for ordinary first registration. A supplied
  key must be a valid recovery blob and must name the same cluster as the
  enrollment key.
  """
  @spec verify_recovery_key(String.t() | nil, String.t()) :: :ok | {:error, String.t()}
  def verify_recovery_key(nil, _cluster_name), do: :ok
  def verify_recovery_key("", _cluster_name), do: :ok

  def verify_recovery_key(recovery_key, cluster_name)
      when is_binary(recovery_key) and is_binary(cluster_name) and cluster_name != "" do
    with {:ok, json} <- Base.decode64(recovery_key),
         {:ok, decoded} <- JSON.decode(json),
         node_id when is_binary(node_id) and node_id != "" <- Map.get(decoded, "node_id"),
         nonce when is_binary(nonce) and nonce != "" <- Map.get(decoded, "nonce"),
         recovery_cluster_name when is_binary(recovery_cluster_name) and recovery_cluster_name != "" <-
           Map.get(decoded, "cluster_name"),
         {:ok, _uuid} <- Ecto.UUID.cast(node_id),
         true <- recovery_cluster_name == cluster_name do
      :ok
    else
      false -> {:error, "RECOVERY_KEY and ENROLLMENT_KEY belong to different clusters"}
      _ -> {:error, "RECOVERY_KEY is invalid"}
    end
  end

  def verify_recovery_key(_recovery_key, _cluster_name), do: {:error, "RECOVERY_KEY is invalid"}

  # =============================================================================
  # Private — Load Enrollment Key
  # =============================================================================

  defp load_enrollment_key do
    enrollment_key = Application.get_env(:edge_agent, :enrollment_key)
    urls = Application.get_env(:edge_agent, :public_enrollment_key_urls, [])

    cond do
      is_binary(enrollment_key) and enrollment_key != "" ->
        Logger.info("Using ENROLLMENT_KEY from configuration")
        {:ok, enrollment_key}

      is_list(urls) and urls != [] ->
        fetch_enrollment_key_from_urls(urls)

      true ->
        {:error, "No enrollment key configured (set ENROLLMENT_KEY or PUBLIC_ENROLLMENT_KEY_URLS)"}
    end
  end

  # Try each URL in order. Transport errors fall through to the next URL;
  # HTTP errors (non-2xx) and extraction failures are terminal — see
  # moduledoc for rationale.
  defp fetch_enrollment_key_from_urls(urls) do
    Enum.reduce_while(urls, {:error, "No URLs to try"}, fn url, _acc ->
      Logger.info("Fetching enrollment key from: #{url}")

      case fetch_enrollment_key_from_url(url) do
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

  defp fetch_enrollment_key_from_url(url) do
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
  # When `PUBLIC_ENROLLMENT_KEY_PATHS` is set, each custom path is tried in
  # order *first*, then the built-in pattern list falls through. With
  # multi-URL configured, paths meant for a third-party endpoint would
  # otherwise break extraction for sibling URLs returning a standard shape;
  # the prepend-not-override semantics let mixed sources coexist.
  @spec extract_from_response(map() | binary() | any()) :: {:ok, String.t()} | {:error, String.t()}
  def extract_from_response(body) when is_map(body) do
    custom_paths = Application.get_env(:edge_agent, :public_enrollment_key_paths, [])

    result =
      case try_custom_paths(body, custom_paths) do
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

  defp try_custom_paths(_body, []), do: nil

  defp try_custom_paths(body, paths) do
    Enum.find_value(paths, fn path ->
      case get_in_path(body, String.split(path, ".")) do
        value when is_binary(value) and value != "" -> value
        _ -> nil
      end
    end)
  end

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
  # Private — Decode Enrollment Key
  # =============================================================================

  defp decode_enrollment_key(enrollment_key) do
    with {:ok, json} <- Base.decode64(enrollment_key, padding: false),
         {:ok, decoded} <- JSON.decode(json),
         admin_urls when is_list(admin_urls) and admin_urls != [] <- Map.get(decoded, "admin_urls"),
         cluster_name when is_binary(cluster_name) and cluster_name != "" <- Map.get(decoded, "cluster_name") do
      {:ok, %{admin_urls: admin_urls, cluster_name: cluster_name}}
    else
      :error -> {:error, "ENROLLMENT_KEY is not valid base64"}
      {:error, _} -> {:error, "ENROLLMENT_KEY is not valid JSON"}
      _ -> {:error, "ENROLLMENT_KEY is missing admin_urls or cluster_name field"}
    end
  end

  # =============================================================================
  # Private — Verify Enrollment Key with Admin
  # =============================================================================

  defp verify_enrollment_key_with_admin(key_blob, admin_urls) do
    case AdminClient.verify_enrollment_key(key_blob, admin_urls) do
      {:ok, %{netmaker_key: netmaker_key, enrollment_key_id: enrollment_key_id}}
      when is_binary(netmaker_key) and netmaker_key != "" and
             is_binary(enrollment_key_id) and enrollment_key_id != "" ->
        Logger.info("Enrollment key verified successfully")
        {:ok, %{netmaker_key: netmaker_key, enrollment_key_id: enrollment_key_id}}

      {:ok, %{enrollment_key_id: nil, error: error}} ->
        Logger.error("Enrollment key rejected by admin: #{error}")
        {:error, "Enrollment key verification failed: #{error}"}

      {:ok, %{netmaker_key: netmaker_key, enrollment_key_id: _enrollment_key_id}}
      when not is_binary(netmaker_key) or netmaker_key == "" ->
        Logger.error("Admin verified enrollment but returned no Netmaker enrollment key")
        {:error, "Admin returned no Netmaker enrollment key"}

      {:error, reason} ->
        Logger.error("Could not reach admin for enrollment verification: #{inspect(reason)}")
        {:error, "Enrollment key verification request failed: #{inspect(reason)}"}
    end
  end
end
