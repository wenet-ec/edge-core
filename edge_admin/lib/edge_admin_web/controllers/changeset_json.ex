# edge_admin/lib/edge_admin_web/controllers/changeset_json.ex
defmodule EdgeAdminWeb.ChangesetJSON do
  @moduledoc """
  Renders changeset errors.
  """

  @doc """
  Renders changeset errors.
  """
  def error(%{changeset: changeset}) do
    # When encoded, the changeset returns its errors
    # as a JSON object. So we just pass it forward.
    %{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)}
  end

  defp translate_error({msg, opts}) do
    # Since you're using EdgeAdmin.Gettext, adjust this if needed
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end
