# edge_agent/lib/edge_agent/self_updates.ex
defmodule EdgeAgent.SelfUpdates do
  @moduledoc """
  Context module for managing self-updates via Watchtower.

  Provides functions to check if self-update is enabled and trigger updates
  through the Watchtower service.
  """

  require Logger

  alias EdgeAgent.EdgeClusters.AdminClient
  alias EdgeAgent.Settings

  @doc """
  Checks if self-update feature is enabled.

  ## Returns
  - `true` if SELF_UPDATE_ENABLED=true
  - `false` otherwise
  """
  @spec enabled? :: boolean()
  def enabled? do
    Application.get_env(:edge_agent, :self_update_enabled, false)
  end

  @doc """
  Triggers a self-update by calling the Watchtower HTTP API.

  ## Behavior
  - Calls Watchtower's `/v1/update` endpoint
  - Uses Bearer token authentication if WATCHTOWER_HTTP_API_TOKEN is configured
  - Handles expected connection errors (timeout/refused/closed) as success signals
    since Watchtower blocks until update completes and agent restarts

  ## Returns
  - `{:ok, body | message_map}` - Update triggered successfully
  - `{:error, reason}` - Failed to trigger update

  ## Examples

      iex> EdgeAgent.SelfUpdates.trigger_update()
      {:ok, %{message: "Update triggered, agent restarting"}}

      iex> EdgeAgent.SelfUpdates.trigger_update()
      {:error, "Self-update service returned status 401: Unauthorized"}
  """
  @spec trigger_update :: {:ok, map() | binary()} | {:error, binary()}
  def trigger_update do
    watchtower_url = Application.get_env(:edge_agent, :watchtower_url, "http://watchtower:8080")
    api_token = Application.get_env(:edge_agent, :watchtower_http_api_token, "")
    update_endpoint = "#{watchtower_url}/v1/update"

    Logger.info("Calling Watchtower service at #{update_endpoint}")

    # Make GET request to Watchtower with Bearer token (10 second timeout)
    headers =
      if api_token == "" do
        []
      else
        [{"authorization", "Bearer #{api_token}"}]
      end

    case Req.get(update_endpoint, headers: headers, receive_timeout: 10_000, retry: false) do
      {:ok, %{status: 200, body: body}} ->
        Logger.info("Self-update triggered successfully")
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        error_msg = "Watchtower returned status #{status}: #{inspect(body)}"
        Logger.error(error_msg)
        {:error, error_msg}

      {:error, %Req.TransportError{reason: reason}} when reason in [:timeout, :econnrefused, :closed] ->
        # Watchtower blocks until update completes, so timeout/connection errors mean agent is restarting
        Logger.info("Self-update triggered successfully (connection #{reason} indicates restart)")
        {:ok, %{message: "Update triggered, agent restarting"}}

      {:error, reason} ->
        error_msg = "Failed to call Watchtower: #{inspect(reason)}"
        Logger.error(error_msg)
        {:error, error_msg}
    end
  end

  @doc """
  Triggers a self-update asynchronously.

  Useful when you need to respond to a caller before the agent restarts.
  The update is triggered in a separate process.

  ## Returns
  - `:ok` - Async task started successfully
  """
  @spec trigger_update_async :: :ok
  def trigger_update_async do
    Task.start(fn ->
      Logger.info("Triggering self-update asynchronously")
      trigger_update()
    end)

    :ok
  end

  @doc """
  Checks for the latest self-update request and triggers update if applicable.

  Used by HTTP fallback mechanism for periodic self-update polling.
  Compares admin's latest self-update timestamp with agent's last check timestamp
  to avoid duplicate updates.

  ## Behavior
  1. Calls admin API to check if latest self-update includes this node
  2. If no update or already processed: Updates last_check timestamp
  3. If new update available: Triggers Watchtower update, then updates timestamp

  ## Returns
  - `:ok` - Check completed successfully (with or without triggering update)
  - `{:error, reason}` - Check or update failed
  """
  @spec check_self_update :: :ok | {:error, term()}
  def check_self_update do
    case AdminClient.check_self_update() do
      {:ok, %{"including_me" => false}} ->
        # No update for this node, record check time
        Settings.set_last_check_self_update_at(DateTime.truncate(DateTime.utc_now(), :second))
        Logger.debug("Self-update check: no update available")
        :ok

      {:ok, %{"including_me" => true, "inserted_at" => inserted_at_str}} ->
        inserted_at = parse_datetime(inserted_at_str)
        last_check = Settings.get_last_check_self_update_at()

        if should_trigger_update?(inserted_at, last_check) do
          Logger.info("Self-update available (inserted_at: #{inserted_at_str}), triggering Watchtower")

          # Trigger update first (in case of failure, we don't update timestamp)
          case trigger_update() do
            {:ok, _} ->
              Settings.set_last_check_self_update_at(DateTime.truncate(DateTime.utc_now(), :second))
              :ok

            {:error, reason} ->
              Logger.error("Failed to trigger self-update: #{inspect(reason)}")
              {:error, reason}
          end
        else
          Logger.debug("Self-update already processed (inserted_at: #{inserted_at_str})")
          :ok
        end

      {:error, reason} ->
        Logger.error("Failed to check self-update: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Determine if update should be triggered
  defp should_trigger_update?(inserted_at, last_check) do
    # Trigger if never checked before OR new update available
    last_check == nil or DateTime.compare(inserted_at, last_check) == :gt
  end

  # Parse ISO8601 datetime string
  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> DateTime.truncate(DateTime.utc_now(), :second)
    end
  end
end
