# edge_agent/lib/edge_agent/edge_clusters/admin_client.ex
defmodule EdgeAgent.EdgeClusters.AdminClient do
  @moduledoc """
  HTTP client for communicating with EdgeAdmin API.

  This module provides a high-level interface for agent-to-admin communication,
  handling authentication, fallback across multiple admin URLs, and error recovery.

  ## Key Concepts

  - **Admin URLs**: List of discovered admin servers from Settings table (VPN)
  - **HTTP Fallback**: Falls back to admin URLs stored in Settings (from enrollment) if no VPN admins found
  - **Fallback Logic**: Try each admin URL until one succeeds
  - **Authentication**: Bearer token authentication for protected endpoints
  - **Automatic Retry**: Falls back to next admin if request fails
  - **Error Handling**: Categorizes errors (HTTP errors, validation, network failures)

  ## Architecture

  The client implements three request patterns:

  1. **Bootstrap Requests** (`verify_enrollment_key/2` → `try_verify/3`)
     - Used before any admin URL is in Settings (pre-VPN-join)
     - URLs come from the decoded enrollment-key blob, not Settings
     - Retries the next URL on 503 (degraded mode) and on network error

  2. **Unauthenticated Requests** (`request_with_fallback/2`)
     - Used for registration (no token yet)
     - URLs come from Settings: VPN admin URLs first, then admin fallback URLs
       stored at enrollment time
     - Falls through to the next URL on network error only

  3. **Authenticated Requests** (`request_with_auth/2`)
     - Used for all post-registration endpoints
     - Requires API token from Settings
     - Adds `Authorization: Bearer <token>` header
     - URL selection identical to (2); same network-error fallback

  ## API Endpoints

  Bootstrap (no auth, URLs from enrollment blob):

  - **POST /api/v1/agents/enrollment_keys/verify** — Verify enrollment key before
    VPN join

  Discovery probe (no auth, raw URL):

  - **GET /api/v1/admins/me/discovery** — Identify reachable admins during
    peer discovery

  Unauthenticated (URLs from Settings):

  - **POST /api/v1/agents/nodes** — Register node and receive API token

  Authenticated (URLs from Settings):

  - **GET /api/v1/agents/command_executions** — List command executions by status
  - **PATCH /api/v1/agents/command_executions/:id/acknowledge** — Acknowledge
    receipt of a pending execution
  - **PATCH /api/v1/agents/command_executions/:id/result** — Report execution
    results
  - **PATCH /api/v1/agents/nodes/me/health_check** — Report node health
    (HTTP-fallback mode)
  - **GET /api/v1/agents/self_updates/check** — Poll for pending self-update
    targeting this node
  - **POST /api/v1/agents/metrics/push** — Push metrics text for HTTP-fallback
    scrape
  - **POST /api/v1/agents/aliases** — Register a friendly DNS alias for this node
  - **POST /api/v1/agents/ssh_usernames/verify_credentials** — Verify SSH
    credentials

  ## Error Handling

  The module returns structured errors:
  - `{:error, :no_admin_urls}` - No admin URLs in Settings (discovery failed)
  - `{:error, :no_api_token}` - Missing API token (not registered yet)
  - `{:error, {:http_error, status, body}}` - HTTP error response
  - `{:error, {:request_failed, reason}}` - Network/connection error
  - `{:error, {:all_requests_failed, msg}}` - All admin URLs failed
  - `{:error, {:validation_error, body}}` - Validation error (422)

  ## Examples

      # Register node (unauthenticated)
      iex> AdminClient.register_node(%{
        node_id: "abc-123",
        id_type: "persistent",
        network_name: "cluster-test",
        http_port: 44000
      })
      {:ok, %{"api_token" => "eyJ...", "proxy_password" => "secret"}}

      # Fetch sent commands (authenticated)
      iex> AdminClient.list_sent_command_executions()
      {:ok, %{data: [%{"id" => "exec-123", "command_text" => "uptime"}], meta: %{}}}

      # Update command execution (authenticated)
      iex> AdminClient.update_command_execution_result("exec-123", %{
        status: "completed",
        exit_code: 0,
        output: "14:23:45 up 3 days"
      })
      :ok

      # Verify SSH credentials (authenticated)
      iex> AdminClient.verify_ssh_credentials("ubuntu", {:password, "secret"})
      {:ok, true}
  """

  alias EdgeAgent.Settings

  require Logger

  # HTTP request timeout options for all admin API calls
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

  Used during VPN peer discovery before any admin URL is stored in Settings.
  No authentication required — hits the public discovery endpoint.

  ## Parameters
  - `url` - Full base URL to probe, e.g. `"http://100.64.0.4:44000"`

  ## Returns
  - `{:ok, admin_name}` - Admin responded and identified itself
  - `{:error, reason}` - Not reachable or not an admin

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

  Called during bootstrap before netclient join. Tries each URL in `admin_urls`
  (from the decoded enrollment key blob) in order. On 503 (degraded mode) or
  network error, tries the next URL. Returns the first successful response.

  ## Parameters
  - `key_blob` - Raw enrollment-key blob string (already decoded by the caller)
  - `admin_urls` - List of admin URLs extracted from the same blob

  ## Returns
  - `{:ok, %{verified: bool, error: String.t(), netmaker_key: String.t()}}` -
    Response from admin (`error` and `netmaker_key` default to `""` if omitted)
  - `{:error, reason}` - All URLs failed or non-retryable error

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
           verified: data["verified"],
           error: data["error"] || "",
           netmaker_key: data["netmaker_key"] || ""
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

  Sends node metadata to admin server and receives API token and proxy password.
  Unauthenticated — agent has no API token until this call returns. Uses the
  Settings URL list (VPN admin URLs, then HTTP fallback URLs).

  ## Parameters
  - `node_params` - Map with node metadata (node_id, id_type, network_name, ports, version)

  ## Returns
  - `{:ok, node_data}` - Registration succeeded, node_data includes api_token and proxy_password
  - `{:error, reason}` - Registration failed

  POST /api/v1/agents/nodes
  """
  @spec register_node(map()) :: {:ok, map()} | {:error, term()}
  def register_node(node_params) do
    path = "/api/v1/agents/nodes"
    payload = node_params

    request_with_fallback(path, fn url ->
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
  Verify SSH credentials (password or public key) for the authenticated node.

  Queries admin server to verify if given username and credential are valid
  for SSH access to this node.

  ## Parameters
  - `username` - SSH username (string)
  - `credential` - Either `{:password, password}` or `{:public_key, public_key}`

  ## Returns
  - `{:ok, true}` - credential verified and valid
  - `{:ok, false}` - username not found or credential incorrect (admin always
    returns 200 with a `verified` field for both cases)
  - `{:error, {:validation_error, body}}` - 422 from admin (malformed request)
  - `{:error, {:http_error, status, body}}` - other non-200 response
  - `{:error, {:request_failed, reason}}` - network/connection error

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

    request_with_auth(path, fn url, headers ->
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

  Base function for fetching command executions with configurable status filter.
  Used during bootstrap and periodic sync to download commands.

  ## Parameters
  - `opts` - Options keyword list:
    - `status` - Filter by status: one of `"sent"`, `"pending"`, `"completed"`,
      `"cancelled"`, `"expired"` (required)
    - `page` - Page number (default: 1)
    - `page_size` - Results per page (default: 100)
    - `order_by` - Sort field (default: "inserted_at")
    - `order_directions` - Sort direction: "asc" or "desc" (default: "asc")

  ## Returns
  - `{:ok, %{data: [command_executions], meta: pagination_meta}}` - Command
    executions with pagination. An empty result is `data: []`, not `:not_found`.
  - `{:error, :not_found}` - Authenticated node not found on admin (e.g. it was
    deleted server-side)
  - `{:error, reason}` - Request failed

  GET /api/v1/agents/command_executions
  """
  @spec list_command_executions(keyword()) :: {:ok, map()} | {:error, term()}
  def list_command_executions(opts \\ []) do
    path = "/api/v1/agents/command_executions"

    # Build query params (status is required)
    query_params = %{
      "status" => Keyword.fetch!(opts, :status),
      "page" => Keyword.get(opts, :page, 1),
      "page_size" => Keyword.get(opts, :page_size, 100),
      "order_by" => Keyword.get(opts, :order_by, "inserted_at"),
      "order_directions" => Keyword.get(opts, :order_directions, "asc")
    }

    request_with_auth(path, fn url, headers ->
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

  Convenience wrapper around `list_command_executions/1`.
  Used to fetch unacknowledged commands that need to be stored and acknowledged.

  ## Parameters
  - `opts` - Options keyword list (see `list_command_executions/1` for details)

  ## Returns
  - Same as `list_command_executions/1`
  """
  @spec list_pending_command_executions(keyword()) :: {:ok, map()} | {:error, term()}
  def list_pending_command_executions(opts \\ []) do
    list_command_executions(Keyword.put(opts, :status, "pending"))
  end

  @doc """
  Lists command executions with status "sent" from admin.

  Convenience wrapper around `list_command_executions/1`.
  Used to fetch acknowledged but not yet executed commands (if needed for reconciliation).

  ## Parameters
  - `opts` - Options keyword list (see `list_command_executions/1` for details)

  ## Returns
  - Same as `list_command_executions/1`
  """
  @spec list_sent_command_executions(keyword()) :: {:ok, map()} | {:error, term()}
  def list_sent_command_executions(opts \\ []) do
    list_command_executions(Keyword.put(opts, :status, "sent"))
  end

  @doc """
  Acknowledge a command execution.

  Notifies admin that agent has received and stored a pending command execution.
  Transitions execution status from "pending" to "sent" on admin side.

  ## Parameters
  - `execution_id` - Command execution ID (string)

  ## Returns
  - `:ok` - Acknowledgment succeeded
  - `{:error, {:http_error, 404, _}}` - Execution not found
  - `{:error, {:http_error, 409, _}}` - Execution not in `"pending"` status
    (already acknowledged or finalized — admin's `ExecutionPendingCheck`)
  - `{:error, reason}` - Acknowledgment failed

  PATCH /api/v1/agents/command_executions/:id/acknowledge
  """
  @spec acknowledge_command_execution(String.t()) :: :ok | {:error, term()}
  def acknowledge_command_execution(execution_id) do
    path = "/api/v1/agents/command_executions/#{execution_id}/acknowledge"

    request_with_auth(path, fn url, headers ->
      opts = Keyword.merge([json: %{}, headers: headers], http_options())

      case Req.patch(url, opts) do
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

  Sends health status (healthy/unhealthy) when using HTTP fallback mode.
  Allows admin to track node health when direct VPN pinging is unavailable.

  ## Parameters
  - `status` - Health status string: "healthy" or "unhealthy"

  ## Returns
  - `{:ok, node}` - Health check reported successfully; `node` is the parsed
    JSON node payload (string-keyed map)
  - `{:error, {:http_error, 422, _}}` - Validation error (invalid status)
  - `{:error, reason}` - Report failed

  PATCH /api/v1/agents/nodes/me/health_check
  """
  @spec report_health_check(String.t()) :: {:ok, map()} | {:error, term()}
  def report_health_check(status) do
    path = "/api/v1/agents/nodes/me/health_check"

    request_with_auth(path, fn url, headers ->
      payload = %{status: status}
      opts = Keyword.merge([json: payload, headers: headers], http_options())

      case Req.patch(url, opts) do
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
  Checks if the latest self-update request includes this node.

  Used by HTTP fallback mechanism for agents to poll for self-updates
  when VPN connectivity is unavailable.

  ## Returns
  - `{:ok, %{"including_me" => boolean, "inserted_at" => String.t() | nil}}` -
    Check succeeded. Map is the raw JSON `data` payload: string keys, ISO8601
    string for `inserted_at`.
  - `{:error, reason}` - Request failed

  ## Examples

      iex> check_self_update()
      {:ok, %{"including_me" => true, "inserted_at" => "2026-01-29T10:30:45Z"}}

      iex> check_self_update()
      {:ok, %{"including_me" => false, "inserted_at" => nil}}

  GET /api/v1/agents/self_updates/check
  """
  @spec check_self_update() :: {:ok, map()} | {:error, term()}
  def check_self_update do
    path = "/api/v1/agents/self_updates/check"

    request_with_auth(path, fn url, headers ->
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

  Reports execution results (output, exit_code, completed_at) back to admin server.
  Called after command execution completes or fails.

  ## Parameters
  - `execution_id` - Command execution ID (string)
  - `command_execution_params` - Map with status, output, exit_code, completed_at

  ## Returns
  - `:ok` - Update succeeded
  - `{:error, {:http_error, 404, _}}` - Execution deleted on admin side
  - `{:error, {:http_error, 409, _}}` - Execution not in a state that accepts
    a result (admin's `ExecutionAcceptsResultCheck`)
  - `{:error, {:http_error, 422, _}}` - Validation error (malformed payload)
  - `{:error, reason}` - Update failed

  PATCH /api/v1/agents/command_executions/:id/result
  """
  @spec update_command_execution_result(String.t(), map()) :: :ok | {:error, term()}
  def update_command_execution_result(execution_id, command_execution_params) do
    path = "/api/v1/agents/command_executions/#{execution_id}/result"
    payload = command_execution_params

    request_with_auth(path, fn url, headers ->
      opts = Keyword.merge([json: payload, headers: headers], http_options())

      case Req.patch(url, opts) do
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

  When VPN is unavailable, agents push metrics to admin for temporary storage.
  Admin caches the metrics and serves them to collectors when they scrape.

  ## Parameters
  - `metrics_type` - Type of metrics: "host", "agent", or "wireguard"
  - `metrics_text` - Raw Prometheus metrics in text format

  ## Returns
  - `{:ok, cache}` - Cache record created/updated
  - `{:error, reason}` - Push failed

  ## Examples

      iex> push_metrics("host", "# HELP node_cpu_seconds_total...")
      {:ok, %{"id" => "cache-123", "node_id" => "node-456", "metrics_type" => "host", "updated_at" => "2025-01-29T12:00:00Z"}}

  POST /api/v1/agents/metrics/push
  """
  @spec push_metrics(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def push_metrics(metrics_type, metrics_text) do
    path = "/api/v1/agents/metrics/push"

    request_with_auth(path, fn url, headers ->
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
  Treats both 201 (created) and 409 (name already taken by another node) as
  `:ok` — alias registration is best-effort and silent conflicts are expected.

  POST /api/v1/agents/aliases
  """
  @spec register_alias(String.t()) :: :ok | {:error, term()}
  def register_alias(name) do
    path = "/api/v1/agents/aliases"

    request_with_auth(path, fn url, headers ->
      payload = %{name: name}
      opts = Keyword.merge([json: payload, headers: headers], http_options())

      case Req.post(url, opts) do
        {:ok, %{status: status}} when status in [201, 409] ->
          :ok

        {:ok, %{status: status, body: body}} ->
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end)
  end

  # Private functions

  defp request_with_fallback(path, request_fn) do
    case get_urls_to_try() do
      [] ->
        Logger.warning("No admin URLs available")
        {:error, :no_admin_urls}

      urls ->
        try_request(urls, path, request_fn)
    end
  end

  defp request_with_auth(path, request_fn) do
    case Settings.get_api_token() do
      nil ->
        Logger.warning("No API token found in Settings")
        {:error, :no_api_token}

      api_token ->
        headers = [{"authorization", "Bearer #{api_token}"}]

        case get_urls_to_try() do
          [] ->
            Logger.warning("No admin URLs available")
            {:error, :no_admin_urls}

          urls ->
            try_request_with_auth(urls, path, headers, request_fn)
        end
    end
  end

  # Get list of URLs to try: VPN admin URLs first, then HTTP fallback URLs from Settings.
  defp get_urls_to_try do
    case Settings.get_admin_urls() do
      [] ->
        fallback_urls = Settings.get_admin_fallback_urls()

        if fallback_urls != [] do
          Logger.info("No VPN admin URLs, using HTTP fallback: #{inspect(fallback_urls)}")
        end

        fallback_urls

      vpn_urls ->
        vpn_urls
    end
  end

  defp try_request([url | remaining_urls], path, request_fn) do
    full_url = "#{url}#{path}"

    case request_fn.(full_url) do
      {:error, {:request_failed, _reason}} when remaining_urls != [] ->
        Logger.debug("Request to #{full_url} failed, trying next URL")
        try_request(remaining_urls, path, request_fn)

      result ->
        result
    end
  end

  defp try_request([], _path, _request_fn) do
    {:error, {:all_requests_failed, "All admin URLs failed"}}
  end

  defp try_request_with_auth([url | remaining_urls], path, headers, request_fn) do
    full_url = "#{url}#{path}"

    case request_fn.(full_url, headers) do
      {:error, {:request_failed, _reason}} when remaining_urls != [] ->
        Logger.debug("Request to #{full_url} failed, trying next URL")
        try_request_with_auth(remaining_urls, path, headers, request_fn)

      result ->
        result
    end
  end

  defp try_request_with_auth([], _path, _headers, _request_fn) do
    {:error, {:all_requests_failed, "All admin URLs failed"}}
  end
end
