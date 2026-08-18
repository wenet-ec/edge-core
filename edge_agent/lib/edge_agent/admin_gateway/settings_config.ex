# edge_agent/lib/edge_agent/admin_gateway/settings_config.ex
defmodule EdgeAgent.AdminGateway.SettingsConfig do
  @moduledoc """
  Refreshes non-secret, Admin Gateway-advertised Settings Config.

  Values are fetched from the authenticated `/api/v1/agents/settings/config`
  endpoint through the normal VPN-first Admin Gateway client. Newly learned
  URLs are prepended locally while known URLs are retained for rolling
  hostname migration.
  """

  alias EdgeAgent.AdminGateway.Client
  alias EdgeAgent.Settings

  require Logger

  @spec refresh() :: :ok
  def refresh do
    case Client.get_settings_config() do
      {:ok, %{"admin_urls" => admin_urls, "core_derp_map_urls" => core_derp_map_urls}}
      when is_list(admin_urls) and is_list(core_derp_map_urls) ->
        Settings.merge_admin_fallback_urls(admin_urls)
        Settings.merge_core_derp_map_urls(core_derp_map_urls)
        Logger.debug("SettingsConfig: refreshed")
        emit_refresh_telemetry(:success)

      {:ok, response} ->
        Logger.warning("SettingsConfig: invalid response: #{inspect(response)}")
        emit_refresh_telemetry(:invalid_response)

      {:error, reason} ->
        Logger.debug("SettingsConfig: refresh failed: #{inspect(reason)}")
        emit_refresh_telemetry(:failure)
    end

    :ok
  end

  defp emit_refresh_telemetry(result) do
    :telemetry.execute(
      [:edge_agent, :settings_config, :refresh],
      %{count: 1},
      %{result: result}
    )
  end
end
