# edge_agent/lib/edge_agent/admin_gateway/settings_config.ex
defmodule EdgeAgent.AdminGateway.SettingsConfig do
  @moduledoc """
  Pulls non-secret, Admin Gateway-advertised Settings Config.

  Values are fetched from the authenticated `/api/v1/agents/settings/config`
  endpoint through the normal VPN-first Admin Gateway client. Admin URLs and
  DERP-map URLs are merged locally for hostname migration; the Ingress
  Tunneling snapshot is replaced as a whole.
  """

  alias EdgeAgent.AdminGateway.Client
  alias EdgeAgent.IngressTunneling
  alias EdgeAgent.Settings

  require Logger

  @spec pull() :: :ok
  def pull do
    case Client.pull_settings_config() do
      {:ok, %{"admin_urls" => admin_urls, "core_derp_map_urls" => core_derp_map_urls} = config}
      when is_list(admin_urls) and is_list(core_derp_map_urls) ->
        Settings.merge_admin_fallback_urls(admin_urls)
        Settings.merge_core_derp_map_urls(core_derp_map_urls)
        pull_ingress_tunneling(config)
        Logger.debug("SettingsConfig: pulled")
        emit_pull_telemetry(:success)

      {:ok, response} ->
        Logger.warning("SettingsConfig: invalid response: #{inspect(response)}")
        emit_pull_telemetry(:invalid_response)

      {:error, reason} ->
        Logger.debug("SettingsConfig: pull failed: #{inspect(reason)}")
        emit_pull_telemetry(:failure)
    end

    :ok
  end

  defp pull_ingress_tunneling(config) do
    case Map.fetch(config, "ingress_tunneling") do
      {:ok, ingress_tunneling} when is_map(ingress_tunneling) ->
        case IngressTunneling.upsert_ingress_tunneling(ingress_tunneling) do
          {:ok, _ingress_tunneling} ->
            :ok

          {:error, reason} ->
            Logger.warning("SettingsConfig: invalid Ingress Tunneling config: #{inspect(reason)}")
        end

      {:ok, value} ->
        Logger.warning("SettingsConfig: invalid Ingress Tunneling config: #{inspect(value)}")

      :error ->
        :ok
    end
  end

  defp emit_pull_telemetry(result) do
    :telemetry.execute(
      [:edge_agent, :settings_config, :pull],
      %{count: 1},
      %{result: result}
    )
  end
end
