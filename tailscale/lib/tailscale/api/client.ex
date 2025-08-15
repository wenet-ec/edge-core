# tailscale/lib/tailscale/api/client.ex
defmodule Tailscale.Api.Client do
  @moduledoc """
  HTTP client for communicating with Headscale VPN API service.

  This module handles the low-level HTTP communication with the Headscale
  VPN service through the wrapper API for node management, enrollment
  key creation, and user operations.
  """

  @behaviour Tailscale.Behaviours.Api

  require Logger

  @impl true
  def get_node_by_hostname(vpn_hostname) do
    url = "#{wrapper_url()}/api/v1/node?user=edge-nodes"

    case http_get(url) do
      {:ok, %{status: 200, body: %{"nodes" => nodes}}} ->
        find_node_by_name(nodes, vpn_hostname)

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def list_nodes_for_user(user) do
    url = "#{wrapper_url()}/api/v1/node?user=#{user}"

    case http_get(url) do
      {:ok, %{status: 200, body: %{"nodes" => nodes}}} ->
        node_list = Enum.map(nodes, &extract_node_info/1)
        {:ok, node_list}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def create_enrollment_key(user) do
    with {:ok, user_id} <- get_user_id(user),
         {:ok, expiration} <- calculate_expiration(),
         {:ok, enrollment_data} <- request_preauth_key(user_id, expiration) do
      {:ok, enrollment_data}
    else
      error -> error
    end
  end

  @impl true
  def get_user(username) do
    case get_user_id(username) do
      {:ok, user_id} ->
        {:ok, %{id: user_id, name: username}}

      {:error, :user_not_found} ->
        {:error, :user_not_found}

      error ->
        error
    end
  end

  # Private functions

  # HTTP client functions that safely call Req
  defp http_get(url, options \\ []) do
    apply(Req, :get, [url, options])
  end

  defp http_post(url, options) do
    apply(Req, :post, [url, options])
  end

  defp wrapper_url do
    case Application.get_env(:tailscale, :vpn_wrapper_url) do
      nil ->
        raise """
        VPN_WRAPPER_URL environment variable or :tailscale :vpn_wrapper_url config is required for API operations.
        This is needed for functions like get_node_by_hostname, create_enrollment_key, etc.
        Edge agents typically don't need this unless using admin-like functionality.
        """
      url -> url
    end
  end

  defp find_node_by_name(nodes, vpn_hostname) do
    case Enum.find(nodes, fn node -> node["name"] == vpn_hostname end) do
      nil ->
        {:error, :node_not_found}

      node ->
        {:ok, extract_node_info(node)}
    end
  end

  defp extract_node_info(node) do
    %{
      vpn_ip: get_primary_ip(node["ipAddresses"]),
      vpn_hostname: node["name"],
      online: node["online"],
      last_seen: node["lastSeen"]
    }
  end

  defp get_primary_ip([ip | _]), do: ip
  defp get_primary_ip([]), do: nil

  # Enrollment key creation functions

  defp get_user_id(username) do
    # Disable retries for better error handling in tests
    req_options = [retry: false]

    case http_get("#{wrapper_url()}/api/v1/user", [params: [name: username]] ++ req_options) do
      {:ok, %{status: 200, body: response}} when is_map(response) ->
        extract_user_id(response, username)

      {:ok, %{status: _status}} ->
        {:error, :user_not_found}

      {:error, %{reason: :econnrefused}} ->
        {:error, :vpn_service_unavailable}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_user_id(%{"users" => users}, username) when is_list(users) do
    case Enum.find(users, fn user -> user["name"] == username end) do
      %{"id" => user_id} -> {:ok, user_id}
      nil -> {:error, :user_not_found}
    end
  end

  defp extract_user_id(%{"id" => user_id}, _username), do: {:ok, user_id}
  defp extract_user_id(_, _username), do: {:error, :user_not_found}

  defp calculate_expiration do
    expiration =
      DateTime.utc_now()
      |> DateTime.add(1, :hour)
      |> DateTime.to_iso8601()

    {:ok, expiration}
  end

  defp request_preauth_key(user_id, expiration) do
    request_body = %{
      user: user_id,
      reusable: false,
      ephemeral: false,
      expiration: expiration,
      aclTags: []
    }

    # Disable retries for better error handling in tests
    req_options = [json: request_body, retry: false]

    case http_post("#{wrapper_url()}/api/v1/preauthkey", req_options) do
      {:ok, %{status: 200, body: %{"preAuthKey" => preauth_data}}} ->
        extract_enrollment_data(preauth_data)

      {:ok, %{status: status, body: body}} ->
        {:error, {:vpn_api_error, status, body}}

      {:error, %{reason: :econnrefused}} ->
        {:error, :vpn_service_unavailable}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_enrollment_data(preauth_data) do
    enrollment_key = %{
      key: preauth_data["key"],
      expiration: preauth_data["expiration"],
      created_at: preauth_data["createdAt"]
    }

    {:ok, enrollment_key}
  end
end