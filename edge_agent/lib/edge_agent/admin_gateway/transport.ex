# edge_agent/lib/edge_agent/admin_gateway/transport.ex
defmodule EdgeAgent.AdminGateway.Transport do
  @moduledoc """
  Shared URL selection and failover transport for Agent-to-Admin Gateway requests.

  A reachable HTTP response is terminal; only transport failures advance to
  the next URL. VPN URLs are always attempted before configured fallbacks.
  """

  alias EdgeAgent.Settings

  require Logger

  @doc false
  @spec request_with_fallback(String.t(), (String.t() -> term())) :: term()
  def request_with_fallback(path, request_fn) do
    case urls_from_settings() do
      [] -> {:error, :no_admin_urls}
      urls -> try_request(urls, path, request_fn)
    end
  end

  @doc false
  @spec request_with_auth(String.t(), (String.t(), [{String.t(), String.t()}] -> term())) :: term()
  def request_with_auth(path, request_fn) do
    case Settings.get_api_token() do
      nil ->
        Logger.warning("No API token found in Settings")
        {:error, :no_api_token}

      token ->
        case urls_from_settings() do
          [] -> {:error, :no_admin_urls}
          urls -> try_request_with_auth(urls, path, [{"authorization", "Bearer #{token}"}], request_fn)
        end
    end
  end

  @doc false
  @spec urls_to_try([String.t()], [String.t()]) :: [String.t()]
  def urls_to_try(vpn_urls, fallback_urls), do: Enum.uniq(vpn_urls ++ fallback_urls)

  defp urls_from_settings do
    vpn_urls = Settings.get_admin_urls()
    fallback_urls = Settings.get_admin_fallback_urls()

    cond do
      vpn_urls == [] and fallback_urls != [] ->
        Logger.info("No VPN admin URLs, using HTTP fallback: #{inspect(fallback_urls)}")

      vpn_urls != [] and fallback_urls != [] ->
        Logger.debug("VPN admin URLs will be tried before public fallback URLs: #{inspect(fallback_urls)}")

      true ->
        :ok
    end

    urls_to_try(vpn_urls, fallback_urls)
  end

  defp try_request([url | remaining], path, request_fn) do
    full_url = "#{url}#{path}"

    case request_fn.(full_url) do
      {:error, {:request_failed, _reason}} when remaining != [] ->
        Logger.debug("Request to #{full_url} failed, trying next URL")
        try_request(remaining, path, request_fn)

      result ->
        result
    end
  end

  defp try_request([], _path, _request_fn), do: {:error, {:all_requests_failed, "All admin URLs failed"}}

  defp try_request_with_auth([url | remaining], path, headers, request_fn) do
    full_url = "#{url}#{path}"

    case request_fn.(full_url, headers) do
      {:error, {:request_failed, _reason}} when remaining != [] ->
        Logger.debug("Request to #{full_url} failed, trying next URL")
        try_request_with_auth(remaining, path, headers, request_fn)

      result ->
        result
    end
  end

  defp try_request_with_auth([], _path, _headers, _request_fn),
    do: {:error, {:all_requests_failed, "All admin URLs failed"}}
end
