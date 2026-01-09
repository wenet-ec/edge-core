# edge_agent/lib/edge_agent/edge_clusters/admin_client.ex
defmodule EdgeAgent.EdgeClusters.AdminClient do
  @moduledoc """
  HTTP client for communicating with EdgeAdmin API.

  This module provides a high-level interface for agent-to-admin communication,
  handling authentication, fallback across multiple admin URLs, and error recovery.

  ## Key Concepts

  - **Admin URLs**: List of discovered admin servers from Settings table
  - **Fallback Logic**: Try each admin URL until one succeeds
  - **Authentication**: Bearer token authentication for protected endpoints
  - **Automatic Retry**: Falls back to next admin if request fails
  - **Error Handling**: Categorizes errors (HTTP errors, validation, network failures)

  ## Architecture

  The client implements two request patterns:

  1. **Unauthenticated Requests** (`request_with_fallback/2`)
     - Used for registration (no token yet)
     - Queries Settings for admin URLs
     - Tries each URL until one succeeds

  2. **Authenticated Requests** (`request_with_auth/2`)
     - Used for all post-registration endpoints
     - Requires API token from Settings
     - Adds `Authorization: Bearer <token>` header
     - Falls back across admin URLs on network errors

  ## API Endpoints

  - **POST /api/agents/nodes** - Register node and receive API token
  - **GET /api/agents/command_executions** - Fetch pending commands
  - **PATCH /api/agents/command_executions/:id** - Report execution results
  - **POST /api/agents/ssh_usernames/verify_credentials** - Verify SSH credentials
  - **POST /api/agents/relays** - Request relay gateway assignment

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
        network_name: "cluster-default",
        http_port: 44000
      })
      {:ok, %{"api_token" => "eyJ...", "proxy_password" => "secret"}}

      # Fetch pending commands (authenticated)
      iex> AdminClient.get_sent_command_executions()
      {:ok, [%{"id" => "exec-123", "command_text" => "uptime"}]}

      # Update command execution (authenticated)
      iex> AdminClient.update_command_execution("exec-123", %{
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

  @doc """
  Register this node with an admin.

  Sends node metadata to admin server and receives API token and proxy password.
  This is the only unauthenticated endpoint (no token yet).

  ## Parameters
  - `node_params` - Map with node metadata (node_id, id_type, network_name, ports, version)

  ## Returns
  - `{:ok, node_data}` - Registration succeeded, node_data includes api_token and proxy_password
  - `{:error, reason}` - Registration failed

  POST /api/agents/nodes
  """
  @spec register_node(map()) :: {:ok, map()} | {:error, term()}
  def register_node(node_params) do
    path = "/api/agents/nodes"
    payload = %{node: node_params}

    request_with_fallback(path, fn url ->
      case Req.post(url, json: payload) do
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
  - `{:ok, false}` - username not found or credential incorrect
  - `{:error, reason}` - request or validation error

  POST /api/agents/ssh_usernames/verify_credentials
  """
  @spec verify_ssh_credentials(String.t(), {:password, String.t()} | {:public_key, String.t()}) ::
          {:ok, boolean()} | {:error, term()}
  def verify_ssh_credentials(username, credential) do
    path = "/api/agents/ssh_usernames/verify_credentials"

    payload =
      case credential do
        {:password, password} ->
          %{ssh_username: %{username: username, password: password}}

        {:public_key, public_key} ->
          %{ssh_username: %{username: username, public_key: public_key}}
      end

    request_with_auth(path, fn url, headers ->
      case Req.post(url, json: payload, headers: headers, receive_timeout: 5000, retry: false) do
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
  Get sent command executions for the authenticated node.

  Fetches list of pending command executions that admin has sent to this node.
  Used during bootstrap and periodic sync to download new commands.

  ## Returns
  - `{:ok, command_executions}` - List of command execution maps
  - `{:error, :not_found}` - Node not found or no commands
  - `{:error, reason}` - Request failed

  GET /api/agents/command_executions
  """
  @spec get_sent_command_executions() :: {:ok, [map()]} | {:error, term()}
  def get_sent_command_executions do
    path = "/api/agents/command_executions"

    request_with_auth(path, fn url, headers ->
      case Req.get(url, headers: headers) do
        {:ok, %{status: 200, body: %{"data" => command_executions}}} ->
          {:ok, command_executions}

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Failed to get command executions, HTTP #{status}: #{inspect(body)}")
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          Logger.warning("Failed to get command executions: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end)
  end

  @doc """
  Creates a relayed node assignment from admin.

  Sends a request to assign this agent to an admin's relay gateway.
  Falls back across all available admin URLs until one succeeds.
  Only the last assignment matters (last write wins).

  ## Returns
  - `{:ok, response}` - Assignment succeeded, response includes relay_admin_name
  - `{:error, :no_api_token}` - No API token found
  - `{:error, :no_admin_urls}` - No admin URLs available
  - `{:error, {:http_error, status, body}}` - HTTP error
  - `{:error, {:all_requests_failed, msg}}` - All admin URLs failed

  POST /api/agents/relays
  """
  @spec create_relayed_node() :: {:ok, map()} | {:error, term()}
  def create_relayed_node do
    path = "/api/agents/relays"

    request_with_auth(path, fn url, headers ->
      case Req.post(url, json: %{}, headers: headers, receive_timeout: 5000, retry: false) do
        {:ok, %{status: 200, body: response}} ->
          Logger.debug("Successfully create relayed node")
          {:ok, response}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Failed to create relayed node, HTTP #{status}: #{inspect(body)}")
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          Logger.warning("Failed to create relayed node: #{inspect(reason)}")
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
  - `{:error, {:http_error, 422, _}}` - Validation error (already completed)
  - `{:error, reason}` - Update failed

  PATCH /api/agents/command_executions/:id
  """
  @spec update_command_execution(String.t(), map()) :: :ok | {:error, term()}
  def update_command_execution(execution_id, command_execution_params) do
    path = "/api/agents/command_executions/#{execution_id}"
    payload = %{command_execution: command_execution_params}

    request_with_auth(path, fn url, headers ->
      case Req.patch(url, json: payload, headers: headers, receive_timeout: 5000, retry: false) do
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

  # Private functions

  defp request_with_fallback(path, request_fn) do
    case Settings.get_admin_urls() do
      [] ->
        Logger.warning("No admin URLs found in Settings")
        {:error, :no_admin_urls}

      admin_urls ->
        try_request(admin_urls, path, request_fn)
    end
  end

  defp request_with_auth(path, request_fn) do
    case Settings.get_api_token() do
      nil ->
        Logger.warning("No API token found in Settings")
        {:error, :no_api_token}

      api_token ->
        headers = [{"authorization", "Bearer #{api_token}"}]

        case Settings.get_admin_urls() do
          [] ->
            Logger.warning("No admin URLs found in Settings")
            {:error, :no_admin_urls}

          admin_urls ->
            try_request_with_auth(admin_urls, path, headers, request_fn)
        end
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
