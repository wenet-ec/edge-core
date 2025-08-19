# edge_agent/lib/edge_agent/admin_client.ex
defmodule EdgeAgent.AdminClient do
  @moduledoc """
  HTTP client for communicating with EdgeAdmin API.
  """

  require Logger

  @admin_base_url "http://100.64.0.1:4000"

  # Node operations

  def get_node(node_id) do
    url = "#{@admin_base_url}/api/nodes/#{node_id}"

    case Req.get(url) do
      {:ok, %{status: 200, body: %{"data" => node_data}}} ->
        {:ok, node_data}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  def create_node(node_params) do
    url = "#{@admin_base_url}/api/nodes"

    payload = %{node: node_params}

    case Req.post(url, json: payload) do
      {:ok, %{status: 201, body: %{"data" => node_data}}} ->
        {:ok, node_data}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  # SSH operations

  def list_ssh_usernames(node_id) do
    url = "#{@admin_base_url}/api/ssh_usernames"
    params = %{node_id: node_id}

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
  end

  def list_ssh_public_keys(ssh_username_id) do
    url = "#{@admin_base_url}/api/ssh_public_keys"
    params = %{ssh_username_id: ssh_username_id}

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
  end

  # Command execution operations

  def update_command_execution(execution_id, command_execution_params) do
    url = "#{@admin_base_url}/api/command_executions/#{execution_id}"

    payload = %{command_execution: command_execution_params}

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
  end
end
