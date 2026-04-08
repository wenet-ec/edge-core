# edge_admin/lib/edge_admin/self_updates/checks/request_completed_check.ex
defmodule EdgeAdmin.SelfUpdates.Checks.RequestCompletedCheck do
  @moduledoc """
  Checks that a self-update request is completed before allowing deletion.

  Prevents deleting requests that are still being processed.
  """

  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest

  @spec check(SelfUpdateRequest.t()) :: :ok | {:error, {:conflict, String.t()}}
  def check(%SelfUpdateRequest{status: "completed"}), do: :ok

  def check(%SelfUpdateRequest{status: status}) do
    {:error,
     {:conflict, "cannot delete self-update request with status '#{status}' - only completed requests can be deleted"}}
  end
end
