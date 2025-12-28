# edge_agent/lib/edge_agent/vpn.ex
defmodule EdgeAgent.Vpn do
  @moduledoc """
  VPN network operations for the edge agent.

  This module handles joining edge cluster VPN networks via Netmaker enrollment keys
  and verifying connection health. It wraps the Nexmaker CLI tool and provides
  enrollment key retrieval from multiple sources.

  ## Key Concepts

  - **Enrollment Key**: Token provided by admin for joining cluster network
  - **Health Check**: Verify netclient connection status (healthy/degraded/unhealthy)
  - **Public Enrollment**: Optional public URL for fetching enrollment keys
  - **Connection Verification**: 5-second wait after join to verify connection

  ## Enrollment Key Sources

  The module supports multiple enrollment key sources with priority order:

  1. **Explicit Key** (`:enrollment_key` config) - Highest priority
  2. **Public URL** (`:public_enrollment_key_url` config) - Fetch via HTTP POST
  3. **Custom Path** (`:public_enrollment_key_path` config) - Extract from nested JSON

  ## Public Enrollment Key Patterns

  When fetching from public URL, the module supports multiple JSON response patterns:
  - Phoenix/Rails/Laravel: `{"data": {"token": "..."}}`
  - Django/Express/NestJS: `{"token": "..."}`
  - Alternative keys: `{"enrollment_key": "..."}`, `{"enrollment_token": "..."}`
  - Deep nesting: `{"result": {"data": {"token": "..."}}}`
  - Custom paths: `"data.attributes.token"` via config

  ## Connection States

  - **Healthy**: All networks connected and operational
  - **Degraded**: Connected but with warnings (acceptable for fresh joins)
  - **Unhealthy**: No networks connected or critical errors

  ## Configuration

  - `:enrollment_key` - Netmaker enrollment token (env: ENROLLMENT_KEY)
  - `:public_enrollment_key_url` - URL to fetch public enrollment key (env: PUBLIC_ENROLLMENT_KEY_URL)
  - `:public_enrollment_key_path` - Custom JSON path for extraction (env: PUBLIC_ENROLLMENT_KEY_PATH)

  ## Examples

      # Join with explicit enrollment key
      config :edge_agent, enrollment_key: "TOKEN=eyJzZXJ2ZXI..."
      iex> Vpn.join_if_needed("node-abc123")
      :ok

      # Join with public URL
      config :edge_agent,
        public_enrollment_key_url: "https://admin.example.com/api/enrollment_keys/public"
      iex> Vpn.join_if_needed("node-abc123")
      :ok

      # Custom extraction path
      config :edge_agent,
        public_enrollment_key_url: "https://api.example.com/enrollment",
        public_enrollment_key_path: "data.attributes.token"
      iex> Vpn.join_if_needed("node-abc123")
      :ok

      # Already connected - skip join
      iex> Vpn.join_if_needed("node-abc123")
      :ok  # Logs: "Already connected to network, skipping join..."
  """

  require Logger

  @doc """
  Joins VPN network using enrollment key if not already connected.

  Checks health status first and only joins if unhealthy (not connected).
  Accepts both healthy and degraded states as "already connected".

  ## Parameters
  - `node_id` - Node identifier used to build node name (e.g., "node-abc123")

  ## Returns
  - `:ok` - Successfully joined or already connected
  - `{:error, reason}` - Failed to join
  """
  @spec join_if_needed(String.t()) :: :ok | {:error, String.t()}
  def join_if_needed(node_id) do
    Logger.info("Checking VPN connection status...")

    case Nexmaker.Cli.health_check() do
      {:ok, :healthy, _info} ->
        Logger.info("Already connected to network, skipping join...")
        :ok

      {:ok, :degraded, _info} ->
        Logger.info("Already connected to network (degraded), skipping join...")
        :ok

      {:ok, :unhealthy, _info} ->
        Logger.info("Not connected to any network, joining VPN...")
        join_network(node_id)
    end
  end

  @doc """
  Joins VPN network using enrollment key and verifies connection.

  Fetches enrollment key from configured source, joins network via netclient,
  waits 5 seconds for connection to stabilize, then verifies health.

  ## Priority
  1. Uses ENROLLMENT_KEY from env if provided
  2. Falls back to fetching key from PUBLIC_ENROLLMENT_KEY_URL if configured

  ## Parameters
  - `node_id` - Node identifier (e.g., "abc123")

  ## Returns
  - `:ok` - Successfully joined and verified
  - `{:error, reason}` - Join or verification failed
  """
  @spec join_network(String.t()) :: :ok | {:error, String.t()}
  def join_network(node_id) do
    node_name = "node-#{node_id}"

    Logger.info("Joining VPN network as #{node_name}...")

    with {:ok, enrollment_key} <- get_enrollment_key(),
         {:ok, _} <- Nexmaker.Cli.join_network(token: enrollment_key, name: node_name),
         :ok <- verify_connection_after_join() do
      Logger.info("Successfully joined VPN network")
      :ok
    else
      {:error, reason} ->
        {:error, "VPN join failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Gets enrollment key with fallback logic.

  Priority:
  1. ENROLLMENT_KEY from config (highest priority)
  2. Fetch from PUBLIC_ENROLLMENT_KEY_URL if configured

  ## Returns
  - `{:ok, token}` - Enrollment key retrieved
  - `{:error, reason}` - No key available
  """
  @spec get_enrollment_key() :: {:ok, String.t()} | {:error, String.t()}
  def get_enrollment_key do
    enrollment_key = Application.get_env(:edge_agent, :enrollment_key)
    public_key_url = Application.get_env(:edge_agent, :public_enrollment_key_url)

    cond do
      # Priority 1: Use explicit enrollment key
      not is_nil(enrollment_key) and enrollment_key != "" ->
        Logger.info("Using ENROLLMENT_KEY from configuration")
        {:ok, enrollment_key}

      # Priority 2: Fetch from public URL
      not is_nil(public_key_url) and public_key_url != "" ->
        Logger.info("Fetching enrollment key from public URL: #{public_key_url}")
        get_public_enrollment_key(public_key_url)

      # No key available
      true ->
        {:error, "No enrollment key configured (set ENROLLMENT_KEY or PUBLIC_ENROLLMENT_KEY_URL)"}
    end
  end

  defp get_public_enrollment_key(url) do
    case Req.post(url) do
      {:ok, %{status: status, body: body}} when status in [200, 201] ->
        # Try to extract token from response body using multiple patterns
        case extract_enrollment_token(body) do
          {:ok, token} ->
            Logger.info("Successfully fetched public enrollment key")
            {:ok, token}

          {:error, reason} ->
            Logger.error("Failed to extract enrollment token from response body: #{reason}. Body: #{inspect(body)}")

            {:error, "Could not extract enrollment token from response: #{reason}"}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to fetch public enrollment key: HTTP #{status}, body: #{inspect(body)}")

        {:error, "Public enrollment key request failed: HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Failed to fetch public enrollment key: #{inspect(reason)}")
        {:error, "Failed to fetch public enrollment key: #{inspect(reason)}"}
    end
  end

  @doc """
  Extracts enrollment token from API response body.

  Supports multiple patterns commonly used in popular frameworks:
  1. Custom path from config: PUBLIC_ENROLLMENT_KEY_PATH (e.g., "data.attributes.token")
  2. Phoenix/Rails/Laravel: {"data": {"token": "..."}}
  3. Django/Express/Spring/ASP.NET: {"token": "..."}
  4. Nested with key_type: {"data": {"key_type": "...", "token": "..."}}
  5. Alternative key names: {"enrollment_key": "..."}, {"enrollment_token": "..."}
  6. Deep nesting: {"result": {"data": {"token": "..."}}}

  ## Returns
  - `{:ok, token}` - Successfully extracted token
  - `{:error, reason}` - Could not find token in response
  """
  @spec extract_enrollment_token(map() | String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def extract_enrollment_token(body) when is_map(body) do
    # Try custom path from config first (highest priority)
    custom_path = Application.get_env(:edge_agent, :public_enrollment_key_path)

    if custom_path != nil and custom_path != "" do
      extract_by_path(body, custom_path)
    else
      # Try common patterns in order of popularity
      try_extraction_patterns(body)
    end
  end

  def extract_enrollment_token(body) when is_binary(body) do
    # If body is a plain string, it might be the token itself
    if String.length(body) > 10 and not String.contains?(body, ["{", "<"]) do
      Logger.debug("Response body is a plain string, treating as token")
      {:ok, String.trim(body)}
    else
      {:error, "Response body is a string but doesn't look like a token"}
    end
  end

  def extract_enrollment_token(_body) do
    {:error, "Response body is not a map or string"}
  end

  # Try extraction using a custom path (e.g., "data.attributes.token")
  defp extract_by_path(body, path) when is_binary(path) do
    keys = String.split(path, ".")

    case get_in_path(body, keys) do
      nil ->
        {:error, "Custom path '#{path}' not found in response"}

      token when is_binary(token) ->
        Logger.debug("Found token using custom path: #{path}")
        {:ok, token}

      _other ->
        {:error, "Custom path '#{path}' does not point to a string value"}
    end
  end

  # Navigate nested map using list of string keys
  defp get_in_path(map, []), do: map

  defp get_in_path(map, [key | rest]) when is_map(map) do
    case Map.get(map, key) do
      nil -> nil
      value -> get_in_path(value, rest)
    end
  end

  defp get_in_path(_non_map, _keys), do: nil

  # Try multiple common patterns
  defp try_extraction_patterns(body) do
    patterns = [
      # Pattern 1: {"data": {"token": "..."}} - Phoenix, Rails, Laravel
      fn -> get_in(body, ["data", "token"]) end,
      # Pattern 2: {"token": "..."} - Django, Express, NestJS, Spring, ASP.NET
      fn -> Map.get(body, "token") end,
      # Pattern 3: {"enrollment_token": "..."}
      fn -> Map.get(body, "enrollment_token") end,
      # Pattern 4: {"enrollment_key": "..."}
      fn -> Map.get(body, "enrollment_key") end,
      # Pattern 5: {"key": "..."}
      fn -> Map.get(body, "key") end,
      # Pattern 6: {"result": {"token": "..."}}
      fn -> get_in(body, ["result", "token"]) end,
      # Pattern 7: {"result": {"data": {"token": "..."}}}
      fn -> get_in(body, ["result", "data", "token"]) end,
      # Pattern 8: {"data": {"enrollment_key": "..."}}
      fn -> get_in(body, ["data", "enrollment_key"]) end,
      # Pattern 9: {"response": {"token": "..."}}
      fn -> get_in(body, ["response", "token"]) end,
      # Pattern 10: {"payload": {"token": "..."}}
      fn -> get_in(body, ["payload", "token"]) end
    ]

    try_patterns(patterns, body)
  end

  defp try_patterns([], _body) do
    {:error, "No matching pattern found for enrollment token"}
  end

  defp try_patterns([pattern_fn | rest], body) do
    case pattern_fn.() do
      token when is_binary(token) and token != "" ->
        Logger.debug("Found token using pattern matching")
        {:ok, token}

      _other ->
        try_patterns(rest, body)
    end
  end

  @doc """
  Waits and verifies VPN connection was established after join.

  Waits 5 seconds for the network to stabilize, then performs health check.
  Accepts both healthy and degraded states as successful (degraded is common after fresh join).

  ## Returns
  - `:ok` - Connection verified (healthy or degraded)
  - `{:error, reason}` - Connection not established (unhealthy)
  """
  @spec verify_connection_after_join() :: :ok | {:error, String.t()}
  def verify_connection_after_join do
    Logger.info("Join command completed, verifying connection...")
    Process.sleep(5000)

    case Nexmaker.Cli.health_check() do
      {:ok, :healthy, info} ->
        networks = info[:networks] || []
        Logger.info("VPN connection verified: joined #{length(networks)} network(s)")
        :ok

      {:ok, :degraded, info} ->
        # Degraded but connected - acceptable for fresh join
        networks = info[:networks] || []
        warnings = info[:warnings] || []
        Logger.warning("VPN connected but degraded: #{inspect(warnings)}")
        Logger.info("Joined #{length(networks)} network(s), continuing despite warnings")
        :ok

      {:ok, :unhealthy, info} ->
        warnings = info[:warnings] || []
        {:error, "Join command succeeded but health check failed: #{Enum.join(warnings, "; ")}"}
    end
  end
end
