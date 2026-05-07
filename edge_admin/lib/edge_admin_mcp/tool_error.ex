# edge_admin/lib/edge_admin_mcp/tool_error.ex
defmodule EdgeAdminMcp.ToolError do
  @moduledoc """
  Renders error reasons as human-readable strings for MCP tool responses.

  Each `message/1` clause maps a domain error reason to the string MCP clients
  see as the tool's error message:

  | Value                 | Rendered message                                                  |
  |-----------------------|-------------------------------------------------------------------|
  | `%Ecto.Changeset{}`   | `"Validation failed: <field> <msg>; ..."` — see `ChangesetErrors` |
  | `{:conflict, reason}` | the reason itself (binary)                                        |
  | `:not_found`          | `"Resource not found"`                                            |
  | `:service_unavailable`| `"A downstream dependency is unavailable — try again shortly"`    |
  | `:degraded_mode`      | `"Cluster is in degraded mode (over capacity) — ..."`             |
  | `%Flop.Meta{}`        | `"Invalid filter or sort parameters"`                             |
  | anything else         | `"An unexpected error occurred"`                                  |

  Tools that need a tailored not-found message (e.g. including the resource id)
  should use `error_response/2` from `EdgeAdminMcp` rather than this module.

  Changeset rendering delegates to `EdgeAdmin.ChangesetErrors.to_flat_string/1`
  — same translator REST uses (`ChangesetJSON`), so message text can't drift
  between surfaces.
  """

  alias EdgeAdmin.ChangesetErrors

  def message(%Ecto.Changeset{} = cs), do: ChangesetErrors.to_flat_string(cs)
  def message({:conflict, reason}) when is_binary(reason), do: reason
  def message(:not_found), do: "Resource not found"
  def message(:service_unavailable), do: "A downstream dependency is unavailable — try again shortly"
  def message(:degraded_mode), do: "Cluster is in degraded mode (over capacity) — try again when capacity recovers"
  def message(%Flop.Meta{}), do: "Invalid filter or sort parameters"
  def message(_), do: "An unexpected error occurred"
end
