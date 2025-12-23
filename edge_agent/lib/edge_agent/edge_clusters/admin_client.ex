# edge_agent/lib/edge_agent/edge_clusters/admin_client.ex
defmodule EdgeAgent.EdgeClusters.AdminClient do
  @moduledoc """
  HTTP client for communicating with EdgeAdmin API.
  Queries Settings table for admin list and tries each admin URL until one succeeds.
  """

  require Logger

  alias EdgeAgent.Settings

  @doc """
  Register this node with an admin.
  POST /api/agents/nodes
  """
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
  POST /api/agents/ssh_usernames/verify_credentials

  ## Parameters
  - `username` - SSH username
  - `credential` - Either `{:password, password}` or `{:public_key, public_key}`

  ## Returns
  - `{:ok, true}` - credential verified
  - `{:ok, false}` - username not found or credential incorrect
  - `{:error, reason}` - request or validation error
  """
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
  GET /api/agents/command_executions
  """
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
  Update a command execution.
  PATCH /api/agents/command_executions/:id
  """
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
