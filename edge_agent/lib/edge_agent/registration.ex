# edge_agent/lib/edge_agent/registration.ex
defmodule EdgeAgent.Registration do
  @moduledoc """
  Registers the Agent with Edge Admin.

  This module owns the registration lifecycle after admin discovery: choosing
  initial registration versus re-registration, building the wire payload,
  persisting returned credentials.
  Registration returns the result to Bootstrap, which owns bootstrap-specific
  timing and telemetry.
  Bootstrap remains responsible only for sequencing these operations.
  """

  alias EdgeAgent.EdgeClusters.AdminClient
  alias EdgeAgent.Settings

  require Logger

  @type identity :: %{node_id: String.t(), recovery_key: String.t() | nil}

  @doc """
  Registers or re-registers an Agent for the discovered network.

  An existing API token selects re-registration. Without one, the Agent uses
  initial registration and may include a recovery key.
  """
  @spec register(identity(), String.t() | nil) :: :ok | {:error, String.t()}
  def register(%{node_id: node_id, recovery_key: recovery_key}, network_name) do
    node_id
    |> registration_request(network_name, recovery_key)
    |> handle_registration_response()
  end

  defp registration_request(node_id, network_name, recovery_key) do
    case Settings.get_api_token() do
      token when is_binary(token) and token != "" ->
        AdminClient.reregister_node(build_reregistration_payload(network_name))

      _ ->
        AdminClient.register_node(build_registration_payload(node_id, network_name, recovery_key))
    end
  end

  defp handle_registration_response({:ok, node_data}) do
    api_token = node_data["api_token"]
    proxy_password = node_data["proxy_password"]

    cond do
      is_nil(api_token) ->
        {:error, "Registration response missing api_token"}

      is_nil(proxy_password) ->
        {:error, "Registration response missing proxy_password"}

      true ->
        persist_registration_credentials(node_data, api_token, proxy_password)
    end
  end

  defp handle_registration_response({:error, reason}), do: {:error, "Registration failed: #{inspect(reason)}"}

  defp persist_registration_credentials(node_data, api_token, proxy_password) do
    admin_urls = node_data["admin_urls"]
    core_derp_map_urls = node_data["core_derp_map_urls"] || []

    case Settings.set_api_token(api_token) do
      {:ok, _setting} ->
        :ok = Settings.set_proxy_password(proxy_password)
        if admin_urls not in [nil, []], do: Settings.merge_admin_fallback_urls(admin_urls)
        Settings.merge_core_derp_map_urls(core_derp_map_urls)
        Logger.info("Successfully registered with admin")
        :ok

      {:error, reason} ->
        {:error, "Failed to persist registration credentials: #{inspect(reason)}"}
    end
  end

  defp build_registration_payload(node_id, network_name, nil) do
    network_name
    |> node_metadata()
    |> Map.put(:node_id, node_id)
  end

  defp build_registration_payload(node_id, network_name, recovery_key) do
    network_name
    |> node_metadata()
    |> Map.merge(%{node_id: node_id, recovery_key: recovery_key})
  end

  defp build_reregistration_payload(network_name), do: node_metadata(network_name)

  defp node_metadata(network_name) do
    # The wire field is `http_port` (Admin's API contract), but the Agent HTTP
    # server's port is configured as `:api_port` from `API_PORT`.
    %{
      network_name: network_name,
      http_port: Application.fetch_env!(:edge_agent, :api_port),
      ssh_port: Application.fetch_env!(:edge_agent, :ssh_port),
      host_metrics_port: Application.fetch_env!(:edge_agent, :host_metrics_port),
      wireguard_metrics_port: Application.fetch_env!(:edge_agent, :wireguard_metrics_port),
      http_proxy_port: Application.fetch_env!(:edge_agent, :http_proxy_port),
      socks5_proxy_port: Application.fetch_env!(:edge_agent, :socks5_proxy_port),
      version: :edge_agent |> Application.spec(:vsn) |> to_string(),
      self_update_enabled: Application.get_env(:edge_agent, :self_update_enabled, false)
    }
  end
end
