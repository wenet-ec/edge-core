# edge_agent/lib/edge_agent/vpn.ex
defmodule EdgeAgent.Vpn do
  @moduledoc """
  VPN network operations for the edge agent.

  Provides functions for joining VPN networks and verifying connections
  using Nexmaker CLI.
  """

  require Logger

  @doc """
  Checks if agent is connected to any VPN network.

  Returns:
  - `{:ok, :connected}` - Connected to at least one network
  - `{:ok, :not_connected}` - Not connected to any network
  - `{:error, reason}` - Failed to check connection
  """
  def check_connection do
    Nexmaker.Cli.check_any_connection()
  end

  @doc """
  Joins VPN network using enrollment key if not already connected.

  Returns:
  - `:ok` - Successfully joined or already connected
  - `{:error, reason}` - Failed to join
  """
  def join_if_needed(node_id) do
    Logger.info("Checking VPN connection status...")

    case check_connection() do
      {:ok, :not_connected} ->
        Logger.info("Not connected to any network, joining VPN...")
        join_network(node_id)

      {:ok, :connected} ->
        Logger.info("Already connected to network, skipping join...")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Joins VPN network using enrollment key and verifies connection.

  Priority:
  1. Uses ENROLLMENT_KEY from env if provided
  2. Falls back to fetching key from PUBLIC_ENROLLMENT_KEY_URL if configured

  Returns:
  - `:ok` - Successfully joined and verified
  - `{:error, reason}` - Join or verification failed
  """
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

  Returns:
  - `{:ok, token}` - Enrollment key retrieved
  - `{:error, reason}` - No key available
  """
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
      {:ok, %{status: status, body: %{"data" => %{"token" => token}}}} when status in [200, 201] ->
        Logger.info("Successfully fetched public enrollment key")
        {:ok, token}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to fetch public enrollment key: HTTP #{status}, body: #{inspect(body)}")
        {:error, "Public enrollment key request failed: HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Failed to fetch public enrollment key: #{inspect(reason)}")
        {:error, "Failed to fetch public enrollment key: #{inspect(reason)}"}
    end
  end

  @doc """
  Waits and verifies VPN connection was established after join.

  Waits 5 seconds for the network to stabilize, then checks connection.

  Returns:
  - `:ok` - Connection verified
  - `{:error, reason}` - Connection not established
  """
  def verify_connection_after_join do
    Logger.info("Join command completed, verifying connection...")
    Process.sleep(5000)

    case check_connection() do
      {:ok, :connected} ->
        Logger.info("VPN connection verified successfully")
        :ok

      {:ok, :not_connected} ->
        {:error, "Join command succeeded but no networks found - enrollment key may be invalid"}

      {:error, reason} ->
        {:error, "Failed to verify join: #{inspect(reason)}"}
    end
  end
end
