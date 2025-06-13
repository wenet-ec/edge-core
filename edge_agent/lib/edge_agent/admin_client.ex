# edge_agent/lib/edge_agent/admin_client.ex
defmodule EdgeAgent.AdminClient do
  @moduledoc """
  HTTP client for communicating with EdgeAdmin API.
  """

  require Logger

  @admin_base_url "http://100.64.0.1:4000"

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
end
