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
  List SSH usernames for a node.
  GET /api/agents/ssh_usernames?node_id=...
  """
  def list_ssh_usernames(node_id) do
    path = "/api/agents/ssh_usernames"
    params = %{node_id: node_id}

    request_with_fallback(path, fn url ->
      case Req.get(url, params: params) do
        {:ok, %{status: 200, body: %{"data" => ssh_usernames}}} ->
          {:ok, ssh_usernames}

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Failed to list SSH usernames for node #{node_id}, HTTP #{status}: #{inspect(body)}")
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          Logger.warning("Failed to list SSH usernames for node #{node_id}: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end)
  end

  @doc """
  List SSH public keys for an SSH username.
  GET /api/agents/ssh_public_keys?ssh_username_id=...
  """
  def list_ssh_public_keys(ssh_username_id) do
    path = "/api/agents/ssh_public_keys"
    params = %{ssh_username_id: ssh_username_id}

    request_with_fallback(path, fn url ->
      case Req.get(url, params: params) do
        {:ok, %{status: 200, body: %{"data" => ssh_public_keys}}} ->
          {:ok, ssh_public_keys}

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, %{status: status, body: body}} ->
          Logger.warning(
            "Failed to list SSH public keys for username #{ssh_username_id}, HTTP #{status}: #{inspect(body)}"
          )

          {:error, {:http_error, status, body}}

        {:error, reason} ->
          Logger.warning("Failed to list SSH public keys for username #{ssh_username_id}: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end)
  end

  @doc """
  Get sent command executions for this node.
  GET /api/agents/command_executions?node_id=...
  """
  def get_sent_command_executions(node_id) do
    path = "/api/agents/command_executions"
    params = %{node_id: node_id}

    request_with_fallback(path, fn url ->
      case Req.get(url, params: params) do
        {:ok, %{status: 200, body: %{"data" => command_executions}}} ->
          {:ok, command_executions}

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Failed to get command executions for node #{node_id}, HTTP #{status}: #{inspect(body)}")
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          Logger.warning("Failed to get command executions for node #{node_id}: #{inspect(reason)}")
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

    request_with_fallback(path, fn url ->
      case Req.patch(url, json: payload) do
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
    case get_admin_urls() do
      [] ->
        Logger.warning("No admin URLs found in Settings")
        {:error, :no_admin_urls}

      admin_urls ->
        try_request(admin_urls, path, request_fn)
    end
  end

  defp get_admin_urls do
    case Settings.get("admin_urls") do
      nil ->
        []

      admin_urls when is_list(admin_urls) ->
        admin_urls

      admin_urls when is_binary(admin_urls) ->
        # Handle case where it might be stored as JSON string
        case Jason.decode(admin_urls) do
          {:ok, urls} when is_list(urls) -> urls
          _ -> []
        end

      _ ->
        []
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
end
