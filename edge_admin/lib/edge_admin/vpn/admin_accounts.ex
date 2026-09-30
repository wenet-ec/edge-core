# edge_admin/lib/edge_admin/vpn/admin_accounts.ex
defmodule EdgeAdmin.Vpn.AdminAccounts do
  @moduledoc "Edge VPN administrator-account operations."

  alias EdgeAdmin.Vpn.Api, as: VpnApi
  alias Nexmaker.Api, as: Api
  alias Nexmaker.Api.Superadmin

  @spec check_admin_account() :: {:ok, boolean()} | {:error, :service_unavailable}
  def check_admin_account, do: VpnApi.normalize_error(Superadmin.check())

  @spec create_admin_account(map()) :: {:ok, map()} | {:error, :already_exists | :service_unavailable}
  def create_admin_account(attrs) do
    case attrs |> Superadmin.create() |> Api.normalize() do
      {:ok, _} = ok ->
        ok

      {:error, {:bad_request, body}} ->
        if String.contains?(Api.extract_message(body), "superadmin user already exists"),
          do: {:error, :already_exists},
          else: {:error, :service_unavailable}

      {:error, _} ->
        {:error, :service_unavailable}
    end
  end
end
