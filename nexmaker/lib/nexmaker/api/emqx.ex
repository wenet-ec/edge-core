defmodule Nexmaker.Api.EMQX do
  @moduledoc """
  EMQX integration management for Netmaker API.

  EMQX is an MQTT broker used by Netmaker for host communication. This module
  provides bulk credential cleanup operations for EMQX deployments.

  ## Use Cases

  - EMQX migration or cluster replacement
  - Auth database corruption recovery
  - Credential sync issues between Netmaker and EMQX
  - Bulk credential cleanup without affecting Netmaker's host database

  ## How It Works

  When you delete EMQX host credentials, hosts will automatically re-authenticate
  and recreate their credentials the next time they check in. This is safe because:

  1. Netmaker's host database remains intact (source of truth)
  2. Hosts automatically regenerate EMQX credentials on next connection
  3. No manual intervention required per-host

  ## Examples

      # Delete all EMQX host credentials (triggers automatic recreation)
      {:ok, _} = Nexmaker.Api.EMQX.delete_all_host_credentials()

  ## Warning

  This operation affects ALL hosts in the EMQX broker. Use with caution in
  production environments. Hosts will temporarily lose MQTT connectivity until
  they re-authenticate (usually within seconds to minutes depending on check-in interval).
  """

  alias Nexmaker.Api

  @doc """
  Deletes all EMQX host credentials.

  Wipes all EMQX authentication database entries for hosts and server credentials.
  Does NOT affect Netmaker's host database - hosts will automatically recreate
  EMQX credentials on next check-in.

  ## Parameters
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - All EMQX credentials deleted
    - `{:error, reason}` - Error occurred

  ## Use Cases

  1. **EMQX Migration**: Moving to a new EMQX cluster
     ```
     # After deploying new EMQX cluster
     {:ok, _} = Nexmaker.Api.EMQX.delete_all_host_credentials()
     # Hosts will auto-recreate credentials in new EMQX
     ```

  2. **Auth Database Recovery**: EMQX auth database corrupted
     ```
     {:ok, _} = Nexmaker.Api.EMQX.delete_all_host_credentials()
     # Clean slate - hosts recreate valid credentials
     ```

  3. **Credential Sync Fix**: Netmaker and EMQX credentials out of sync
     ```
     {:ok, _} = Nexmaker.Api.EMQX.delete_all_host_credentials()
     # Forces credential regeneration from Netmaker source of truth
     ```

  ## Examples

      {:ok, _} = Nexmaker.Api.EMQX.delete_all_host_credentials()
  """
  @spec delete_all_host_credentials(keyword()) :: {:ok, any()} | {:error, any()}
  def delete_all_host_credentials(opts \\ []) do
    Api.request(:delete, "/api/emqx/hosts", opts)
  end
end
