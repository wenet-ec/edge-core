# edge_admin/lib/edge_admin/vpn/api.ex
defmodule EdgeAdmin.Vpn.Api do
  @moduledoc "Normalizes Edge VPN API results for the Admin domain."

  alias Nexmaker.Api
  alias Nexmaker.Api.Server

  @spec normalize_error(term()) :: {:ok, term()} | {:error, :not_found | :service_unavailable}
  def normalize_error(result) do
    case Api.normalize(result) do
      {:ok, _} = ok -> ok
      {:error, :not_found} -> {:error, :not_found}
      {:error, _} -> {:error, :service_unavailable}
    end
  end

  @spec health_check(keyword()) :: :ok | {:error, :service_unavailable}
  def health_check(opts) do
    case opts |> Server.status() |> normalize_error() do
      {:ok, _status} -> :ok
      error -> error
    end
  end
end
