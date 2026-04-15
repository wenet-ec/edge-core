# edge_agent/lib/edge_agent_web/controllers/changeset_json.ex
defmodule EdgeAgentWeb.Controllers.ChangesetJSON do
  alias EdgeAgentWeb.ResponseEnvelope

  def error(%{conn: conn, changeset: changeset}) do
    details = Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
    ResponseEnvelope.error(conn, "validation_failed", "Validation failed", details)
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end
