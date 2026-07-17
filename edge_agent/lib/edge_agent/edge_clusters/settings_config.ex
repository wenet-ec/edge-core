# edge_agent/lib/edge_agent/edge_clusters/settings_config.ex
defmodule EdgeAgent.EdgeClusters.SettingsConfig do
  @moduledoc """
  Refreshes non-secret, Admin-advertised connectivity configuration.

  Values are fetched from the authenticated `/api/v1/agents/settings/config`
  endpoint through the normal VPN-first Admin client. Newly learned URLs are
  prepended locally while known URLs are retained for rolling hostname migration.
  """

  alias EdgeAgent.EdgeClusters.AdminClient
  alias EdgeAgent.Settings

  require Logger

  @spec refresh() :: :ok
  def refresh do
    case AdminClient.get_connectivity_config() do
      {:ok, %{"admin_urls" => admin_urls, "core_derp_map_urls" => core_derp_map_urls}}
      when is_list(admin_urls) and is_list(core_derp_map_urls) ->
        Settings.merge_admin_fallback_urls(admin_urls)
        Settings.merge_core_derp_map_urls(core_derp_map_urls)
        Logger.debug("SettingsConfig: refreshed")

      {:ok, response} ->
        Logger.warning("SettingsConfig: invalid response: #{inspect(response)}")

      {:error, reason} ->
        Logger.debug("SettingsConfig: refresh failed: #{inspect(reason)}")
    end

    :ok
  end
end
