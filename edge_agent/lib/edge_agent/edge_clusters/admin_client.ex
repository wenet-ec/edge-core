# edge_agent/lib/edge_agent/edge_clusters/admin_client.ex
defmodule EdgeAgent.EdgeClusters.AdminClient do
  @moduledoc """
  HTTP client for Agent-to-Admin API calls.

  Bootstrap enrollment uses URLs from the decoded enrollment-key blob. All
  post-registration calls use Settings URLs through `Transport`: VPN-discovered
  Admin URLs first, then public fallback URLs on transport failure. Reachable
  HTTP responses are terminal.
  """

  alias EdgeAgent.EdgeClusters.AdminClient.Transport

  require Logger

  defp http_options do
    timeout = Application.get_env(:edge_agent, :admin_call_timeout, 10_000)

    [
      receive_timeout: timeout,
      connect_options: [timeout: timeout],
      retry: false
    ]
  end

  @doc """
  Probes a raw admin URL to check if it is a reachable EdgeAdmin instance.

  GET /api/v1/admins/me/discovery
  """
  @spec probe(String.t()) :: {:ok, String.t()} | {:error, term()}
  def probe(url) do
    timeout = Application.get_env(:edge_agent, :admin_discovery_timeout, 5_000)

    opts = [
      receive_timeout: timeout,
      connect_options: [timeout: timeout],
      retry: false
    ]

    case Req.get("#{url}/api/v1/admins/me/discovery", opts) do
      {:ok, %{status: 200, body: %{"data" => %{"name" => admin_name}}}} ->
        {:ok, admin_name}

      {:ok, %{status: 200}} ->
        {:error, :unexpected_body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @doc """
  Verify an enrollment key with admin before joining the VPN.

  Retries the next enrollment URL on degraded-mode 503 and network errors.

  POST /api/v1/agents/enrollment_keys/verify
  """
  @spec verify_enrollment_key(String.t(), [String.t()]) :: {:ok, map()} | {:error, term()}
  def verify_enrollment_key(key_blob, admin_urls) do
    path = "/api/v1/agents/enrollment_keys/verify"
    payload = %{key: key_blob}

    try_verify(admin_urls, path, payload)
  end

  defp try_verify([], _path, _payload) do
    {:error, {:all_requests_failed, "All admin URLs failed during enrollment key verification"}}
  end

  defp try_verify([url | rest], path, payload) do
    full_url = "#{url}#{path}"
    opts = Keyword.merge([json: payload], http_options())

    case Req.post(full_url, opts) do
      {:ok, %{status: 200, body: %{"data" => data}}} ->
        {:ok,
         %{
           error: data["error"] || "",
           vpn_enrollment_key: data["vpn_enrollment_key"] || "",
           enrollment_key_id: data["enrollment_key_id"]
         }}

      {:ok, %{status: 503}} ->
        Logger.warning("Admin at #{url} is in degraded mode, trying next URL...")
        try_verify(rest, path, payload)

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Enrollment key verification failed at #{url}, HTTP #{status}: #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.warning("Enrollment key verification request failed at #{url}: #{inspect(reason)}, trying next URL...")
        try_verify(rest, path, payload)
    end
  end

  @doc """
  Register this node with an admin.

  POST /api/v1/agents/nodes/register
  """
  @spec register_node(map()) :: {:ok, map()} | {:error, term()}
  def register_node(node_params) do
    path = "/api/v1/agents/nodes/register"
    payload = node_params

    Transport.request_with_fallback(path, fn url ->
      opts = Keyword.merge([json: payload], http_options())

      case Req.post(url, opts) do
        {:ok, %{status: 201, body: %{"data" => node_data}}} ->
          {:ok, node_data}

        {:ok, %{status: status, body: body}} ->
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end)
  end

  @doc """
  Re-register this authenticated node with an admin.

  POST /api/v1/agents/nodes/reregister
  """
  @spec reregister_node(map()) :: {:ok, map()} | {:error, term()}
  def reregister_node(node_params) do
    Transport.request_with_auth("/api/v1/agents/nodes/reregister", fn url, headers ->
      opts = Keyword.merge([json: node_params, headers: headers], http_options())

      case Req.post(url, opts) do
        {:ok, %{status: 200, body: %{"data" => node_data}}} -> {:ok, node_data}
        {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
        {:error, reason} -> {:error, {:request_failed, reason}}
      end
    end)
  end

  @doc """
  Fetches refreshable, non-secret Settings Config for this agent.

  GET /api/v1/agents/settings/config
  """
  @spec get_settings_config() :: {:ok, map()} | {:error, term()}
  def get_settings_config do
    Transport.request_with_auth("/api/v1/agents/settings/config", fn url, headers ->
      opts = Keyword.merge([headers: headers], http_options())

      case Req.get(url, opts) do
        {:ok, %{status: 200, body: %{"data" => data}}} when is_map(data) ->
          {:ok, data}

        {:ok, %{status: status, body: body}} ->
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end)
  end

  @doc """
  Verify SSH credentials (password or public key) for the authenticated node.

  POST /api/v1/agents/ssh_usernames/verify_credentials
  """
  @spec verify_ssh_credentials(String.t(), {:password, String.t()} | {:public_key, String.t()}) ::
          {:ok, boolean()} | {:error, term()}
  def verify_ssh_credentials(username, credential) do
    path = "/api/v1/agents/ssh_usernames/verify_credentials"

    payload =
      case credential do
        {:password, password} ->
          %{username: username, password: password}

        {:public_key, public_key} ->
          %{username: username, public_key: public_key}
      end

    Transport.request_with_auth(path, fn url, headers ->
      opts = Keyword.merge([json: payload, headers: headers], http_options())

      case Req.post(url, opts) do
        {:ok, %{status: 200, body: %{"data" => %{"verified" => verified}}}} ->
          {:ok, verified}

        {:ok, %{status: 422, body: body}} ->
          Logger.warning("SSH credentials verification validation failed: #{inspect(body)}")
          {:error, {:validation_error, body}}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Failed to verify SSH credentials, HTTP #{status}: #{inspect(body)}")
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          Logger.warning("Failed to verify SSH credentials: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end)
  end

  @doc """
  Lists command executions from admin with filtering and pagination.

  `:status` is required. Empty results are returned as `data: []`, not
  `:not_found`.

  GET /api/v1/agents/command_executions
  """
  @spec list_command_executions(keyword()) :: {:ok, map()} | {:error, term()}
  def list_command_executions(opts \\ []) do
    path = "/api/v1/agents/command_executions"

    query_params = %{
      "status" => Keyword.fetch!(opts, :status),
      "page" => Keyword.get(opts, :page, 1),
      "page_size" => Keyword.get(opts, :page_size, 100),
      "sort" => Keyword.get(opts, :sort, "inserted_at")
    }

    Transport.request_with_auth(path, fn url, headers ->
      opts = Keyword.merge([headers: headers, params: query_params], http_options())

      case Req.get(url, opts) do
        {:ok, %{status: 200, body: %{"data" => command_executions, "meta" => meta}}} ->
          {:ok, %{data: command_executions, meta: meta}}

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Failed to list command executions, HTTP #{status}: #{inspect(body)}")
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          Logger.warning("Failed to list command executions: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end)
  end

  @doc """
  Lists command executions with status "pending" from admin.

  Used to fetch unacknowledged commands that need to be stored and acknowledged.
  """
  @spec list_pending_command_executions(keyword()) :: {:ok, map()} | {:error, term()}
  def list_pending_command_executions(opts \\ []) do
    list_command_executions(Keyword.put(opts, :status, "pending"))
  end

  @doc """
  Lists command executions with status "sent" from admin.

  Used to fetch acknowledged but not yet executed commands (if needed for reconciliation).
  """
  @spec list_sent_command_executions(keyword()) :: {:ok, map()} | {:error, term()}
  def list_sent_command_executions(opts \\ []) do
    list_command_executions(Keyword.put(opts, :status, "sent"))
  end

  @doc """
  Acknowledge a command execution.

  Transitions Admin-side status from `"pending"` to `"sent"`.

  POST /api/v1/agents/command_executions/:id/acknowledge
  """
  @spec acknowledge_command_execution(String.t()) :: :ok | {:error, term()}
  def acknowledge_command_execution(execution_id) do
    path = "/api/v1/agents/command_executions/#{execution_id}/acknowledge"

    Transport.request_with_auth(path, fn url, headers ->
      opts = Keyword.merge([json: %{}, headers: headers], http_options())

      case Req.post(url, opts) do
        {:ok, %{status: status}} when status in 200..299 ->
          Logger.debug("Successfully acknowledged command execution #{execution_id}")
          :ok

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Failed to acknowledge command execution #{execution_id}, HTTP #{status}: #{inspect(body)}")
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          Logger.warning("Failed to acknowledge command execution #{execution_id}: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end)
  end

  @doc """
  Reports node health check status to admin.

  POST /api/v1/agents/nodes/me/health_check
  """
  @spec report_health_check(String.t()) :: {:ok, map()} | {:error, term()}
  def report_health_check(status) do
    path = "/api/v1/agents/nodes/me/health_check"

    Transport.request_with_auth(path, fn url, headers ->
      payload = %{status: status}
      opts = Keyword.merge([json: payload, headers: headers], http_options())

      case Req.post(url, opts) do
        {:ok, %{status: 200, body: %{"data" => node}}} ->
          Logger.debug("Successfully reported health check: #{status}")
          {:ok, node}

        {:ok, %{status: status_code, body: body}} ->
          Logger.warning("Failed to report health check, HTTP #{status_code}: #{inspect(body)}")
          {:error, {:http_error, status_code, body}}

        {:error, reason} ->
          Logger.warning("Failed to report health check: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end)
  end

  @doc """
  Pushes a diagnostic report to Admin through the normal
  authenticated VPN-first/fallback client.

  POST /api/v1/agents/diagnostics/push
  """
  @spec push_diagnostics(map()) :: {:ok, map()} | {:error, term()}
  def push_diagnostics(diagnostic) when is_map(diagnostic) do
    path = "/api/v1/agents/diagnostics/push"

    Transport.request_with_auth(path, fn url, headers ->
      opts = Keyword.merge([json: %{diagnostic: diagnostic}, headers: headers], http_options())

      case Req.post(url, opts) do
        {:ok, %{status: 200, body: %{"data" => data}}} when is_map(data) -> {:ok, data}
        {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
        {:error, reason} -> {:error, {:request_failed, reason}}
      end
    end)
  end

  @doc """
  Checks if the latest self-update request includes this node.

  GET /api/v1/agents/self_updates/check
  """
  @spec check_self_update() :: {:ok, map()} | {:error, term()}
  def check_self_update do
    path = "/api/v1/agents/self_updates/check"

    Transport.request_with_auth(path, fn url, headers ->
      opts = Keyword.merge([headers: headers], http_options())

      case Req.get(url, opts) do
        {:ok, %{status: 200, body: %{"data" => data}}} ->
          Logger.debug("Self-update check completed: including_me=#{data["including_me"]}")
          {:ok, data}

        {:ok, %{status: status_code, body: body}} ->
          Logger.warning("Failed to check self-update, HTTP #{status_code}: #{inspect(body)}")
          {:error, {:http_error, status_code, body}}

        {:error, reason} ->
          Logger.warning("Failed to check self-update: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end)
  end

  @doc """
  Update a command execution with results.

  POST /api/v1/agents/command_executions/:id/report_result
  """
  @spec report_command_execution_result(String.t(), map()) :: :ok | {:error, term()}
  def report_command_execution_result(execution_id, command_execution_params) do
    path = "/api/v1/agents/command_executions/#{execution_id}/report_result"
    payload = command_execution_params

    Transport.request_with_auth(path, fn url, headers ->
      opts = Keyword.merge([json: payload, headers: headers], http_options())

      case Req.post(url, opts) do
        {:ok, %{status: status}} when status in 200..299 ->
          Logger.debug("Successfully updated command execution #{execution_id}")
          :ok

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Failed to update command execution #{execution_id}, HTTP #{status}: #{inspect(body)}")
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          Logger.warning("Failed to update command execution #{execution_id}: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end)
  end

  @doc """
  Pushes metrics cache to admin for HTTP fallback mode.

  POST /api/v1/agents/metrics/push
  """
  @spec push_metrics(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def push_metrics(metrics_type, metrics_text) do
    path = "/api/v1/agents/metrics/push"

    Transport.request_with_auth(path, fn url, headers ->
      payload = %{
        metrics_type: metrics_type,
        metrics_text: metrics_text
      }

      opts = Keyword.merge([json: payload, headers: headers], http_options())

      case Req.post(url, opts) do
        {:ok, %{status: 200, body: %{"data" => data}}} ->
          Logger.debug("Pushed #{metrics_type} metrics to admin")
          {:ok, data}

        {:ok, %{status: status_code, body: body}} ->
          Logger.warning("Failed to push #{metrics_type} metrics, HTTP #{status_code}: #{inspect(body)}")
          {:error, {:http_error, status_code, body}}

        {:error, reason} ->
          Logger.warning("Failed to push #{metrics_type} metrics: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end)
  end

  @doc """
  Registers an alias (friendly name) for this node with admin.

  Called during bootstrap for each name in the ALIASES env var.

  POST /api/v1/agents/aliases
  """
  @spec register_alias(String.t()) :: :ok | {:error, term()}
  def register_alias(name) do
    path = "/api/v1/agents/aliases"

    Transport.request_with_auth(path, fn url, headers ->
      payload = %{name: name}
      opts = Keyword.merge([json: payload, headers: headers], http_options())

      case Req.post(url, opts) do
        {:ok, %{status: 201}} ->
          :ok

        {:ok, %{status: 409, body: body}} ->
          {:error, {:conflict, body}}

        {:ok, %{status: status, body: body}} ->
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end)
  end

  @doc false
  # Kept pure and public for unit testing. VPN URLs are deliberately not
  # discarded merely because public fallbacks exist: their lower latency is the
  # preferred path. The fallback URLs follow them so the same request can still
  # escape a broken VPN path without waiting for another scheduler tick.
  @spec urls_to_try([String.t()], [String.t()]) :: [String.t()]
  def urls_to_try(vpn_urls, fallback_urls), do: Transport.urls_to_try(vpn_urls, fallback_urls)
end
