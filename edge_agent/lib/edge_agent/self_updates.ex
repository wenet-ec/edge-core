# edge_agent/lib/edge_agent/self_updates.ex
defmodule EdgeAgent.SelfUpdates do
  @moduledoc """
  Context module for managing self-updates via Watchtower.

  Provides functions to check if self-update is enabled and trigger updates
  through the Watchtower service.

  ## Behaviour notes

  - **Boot-time trigger on fresh agents**: `check_self_update/0` triggers
    Watchtower whenever `last_check_self_update_at` is `nil`, regardless of
    how old the admin-side request is. A fresh agent that joins a cluster
    with an old self-update record on file will pull and restart on first
    poll. There is no "older than N" guard today.
  - **`trigger_update_async/0` is fire-and-forget**: the spawned task contains
    unexpected failures and logs them instead of surfacing them to the HTTP
    caller. Acceptable in the current call site because the agent may restart
    mid-call after Watchtower accepts the update.
  """

  alias EdgeAgent.EdgeClusters.AdminClient
  alias EdgeAgent.Settings

  require Logger

  @doc """
  Checks if self-update feature is enabled.
  """
  @spec enabled? :: boolean()
  def enabled? do
    Application.get_env(:edge_agent, :self_update_enabled, false)
  end

  @doc """
  Returns `:ok` if self-update is enabled, `{:error, :forbidden}` otherwise.

  Used by the controller to let the fallback handle the 403 response uniformly.
  """
  @spec check_enabled() :: :ok | {:error, :forbidden}
  def check_enabled do
    if enabled?(), do: :ok, else: {:error, :forbidden}
  end

  @doc """
  Triggers a self-update by calling the Watchtower HTTP API.

  Calls Watchtower's `/v1/update?async=true` endpoint, using bearer-token
  authentication when `WATCHTOWER_HTTP_API_TOKEN` is configured.
  """
  @spec trigger_update :: {:ok, map() | binary()} | {:error, binary()}
  def trigger_update do
    watchtower_url = Application.get_env(:edge_agent, :watchtower_url, "")
    api_token = Application.get_env(:edge_agent, :watchtower_http_api_token, "")

    case build_update_endpoint(watchtower_url) do
      {:ok, update_endpoint} ->
        Logger.info("Calling Watchtower service at #{update_endpoint}")

        # POST to Watchtower's POST-only /v1/update with its async query parameter.
        # The accepted response arrives before Watchtower restarts the agent.
        headers =
          if api_token == "" do
            []
          else
            [{"authorization", "Bearer #{api_token}"}]
          end

        case Req.post(update_endpoint, headers: headers, receive_timeout: 10_000, retry: false) do
          {:ok, %{status: 202, body: body}} ->
            Logger.info("Self-update accepted successfully")
            {:ok, body}

          {:ok, %{status: status, body: body}} ->
            error_msg = "Watchtower returned status #{status}: #{inspect(body)}"
            Logger.error(error_msg)
            {:error, error_msg}

          {:error, reason} ->
            error_msg = "Failed to call Watchtower: #{inspect(reason)}"
            Logger.error(error_msg)
            {:error, error_msg}
        end

      {:error, error_msg} ->
        Logger.error(error_msg)
        {:error, error_msg}
    end
  end

  @doc """
  Triggers a self-update asynchronously.

  Useful when you need to respond to a caller before the agent restarts.
  The update is triggered in a separate process.
  """
  @spec trigger_update_async :: :ok
  def trigger_update_async do
    case Application.get_env(:edge_agent, :self_update_async_trigger) do
      trigger when is_function(trigger, 0) -> trigger.()
      _ -> start_update_task()
    end

    :ok
  end

  @doc false
  @spec start_update_task() :: :ok
  def start_update_task do
    Task.start(fn ->
      Logger.info("Triggering self-update asynchronously")

      try do
        trigger_update()
      rescue
        error ->
          Logger.error("Self-update task failed: #{Exception.message(error)}")
          {:error, Exception.message(error)}
      end
    end)

    :ok
  end

  @doc false
  @spec build_update_endpoint(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def build_update_endpoint(watchtower_url) when is_binary(watchtower_url) do
    trimmed_url = String.trim_trailing(watchtower_url, "/")
    uri = URI.parse(trimmed_url)

    cond do
      uri.scheme not in ["http", "https"] ->
        {:error, "Invalid WATCHTOWER_URL: expected http or https URL, got #{inspect(watchtower_url)}"}

      is_nil(uri.host) or uri.host == "" ->
        {:error, "Invalid WATCHTOWER_URL: host is required, got #{inspect(watchtower_url)}"}

      true ->
        {:ok, "#{trimmed_url}/v1/update?async=true"}
    end
  end

  @doc """
  Checks for the latest self-update request and triggers update if applicable.

  Used by HTTP fallback mechanism for periodic self-update polling.
  Compares admin's latest self-update timestamp with agent's last check timestamp
  to avoid duplicate updates.
  """
  @spec check_self_update :: :ok | {:error, term()}
  def check_self_update do
    case AdminClient.check_self_update() do
      {:ok, %{"including_me" => false}} ->
        Settings.set_last_check_self_update_at(DateTime.truncate(DateTime.utc_now(), :second))
        Logger.debug("Self-update check: no update available")
        :ok

      {:ok, %{"including_me" => true, "inserted_at" => inserted_at_str}} ->
        inserted_at = parse_datetime(inserted_at_str)
        last_check = Settings.get_last_check_self_update_at()

        if should_trigger_update?(inserted_at, last_check) do
          Logger.info("Self-update available (inserted_at: #{inserted_at_str}), triggering Watchtower")

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

  # Determine if update should be triggered.
  #
  # `inserted_at == nil` means the admin payload was missing or unparseable —
  # don't trigger on bad data.
  # `last_check == nil` means we've never checked before — trigger so a
  # fresh agent can pick up an outstanding self-update request.
  # Otherwise trigger only if `inserted_at` is strictly newer than the last
  # check we recorded.
  @doc false
  # Public for unit testing. Decides whether to trigger Watchtower based on
  # the admin's reported `inserted_at` and our last-check timestamp.
  #
  # nil inserted_at → false (admin payload was missing/unparseable; refuse to
  # act on bad data, otherwise we'd loop-restart on every check).
  # nil last_check → true (fresh agent; pick up any outstanding request).
  # Both set → trigger only if inserted_at is strictly newer than last_check.
  @spec should_trigger_update?(DateTime.t() | nil, DateTime.t() | nil) :: boolean()
  def should_trigger_update?(nil, _last_check), do: false
  def should_trigger_update?(_inserted_at, nil), do: true

  def should_trigger_update?(%DateTime{} = inserted_at, %DateTime{} = last_check) do
    DateTime.after?(inserted_at, last_check)
  end

  @doc false
  # Public for unit testing. Parse ISO 8601 datetime string. Returns `nil`
  # (not "now") on parse error so should_trigger_update?/2 can refuse to act
  # on bad data.
  @spec parse_datetime(String.t() | nil) :: DateTime.t() | nil
  def parse_datetime(nil), do: nil

  def parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} ->
        dt

      {:error, reason} ->
        Logger.warning("Self-update: malformed inserted_at #{inspect(str)} (#{inspect(reason)})")
        nil
    end
  end
end
