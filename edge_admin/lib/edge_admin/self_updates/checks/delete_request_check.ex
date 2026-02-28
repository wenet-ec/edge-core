# edge_admin/lib/edge_admin/self_updates/checks/delete_request_check.ex
defmodule EdgeAdmin.SelfUpdates.Checks.DeleteRequestCheck do
  @moduledoc """
  Precondition check for self-update request deletion.

  A request can only be deleted when it is completed.
  This prevents deleting requests that are still being processed.
  """

  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest

  @spec check(SelfUpdateRequest.t()) :: :ok | {:error, {:conflict, String.t()}}
  def check(%SelfUpdateRequest{status: "completed"}), do: :ok

  def check(%SelfUpdateRequest{status: status}) do
    {:error,
     {:conflict, "cannot delete self-update request with status '#{status}' - only completed requests can be deleted"}}
  end
end
