# edge_admin/lib/edge_admin/self_updates/rules/deletion_rules.ex
defmodule EdgeAdmin.SelfUpdates.Rules.DeletionRules do
  @moduledoc """
  Deletion validation rules for self-update requests.
  """

  alias Ecto.Changeset
  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest

  @doc """
  Validates that a self-update request can be deleted.

  Only completed requests can be deleted to prevent deleting requests
  that are still being processed.

  ## Parameters
  - `request` - The request to validate

  ## Returns
  - `:ok` - Request can be deleted
  - `{:error, changeset}` - Validation failed
  """
  @spec validate_request_deletion(SelfUpdateRequest.t()) ::
          :ok | {:error, Changeset.t()}
  def validate_request_deletion(%SelfUpdateRequest{status: "completed"}) do
    :ok
  end

  def validate_request_deletion(%SelfUpdateRequest{} = request) do
    changeset =
      request
      |> Changeset.change()
      |> Changeset.add_error(
        :status,
        "cannot delete self-update request that is #{request.status}. Only completed requests can be deleted"
      )

    {:error, changeset}
  end
end
