# edge_admin/lib/edge_admin_mcp/tool_error.ex
defmodule EdgeAdminMcp.ToolError do
  @moduledoc """
  Renders error reasons as human-readable strings for MCP tool responses.

  Each `message/1` clause maps a domain error reason to the string MCP clients
  see as the tool's error message:

  | Value                 | Rendered message                                    |
  |-----------------------|-----------------------------------------------------|
  | `%Ecto.Changeset{}`   | `"Validation failed: <traversed errors>"`           |
  | `{:conflict, reason}` | the reason itself (binary)                          |
  | `:not_found`          | `"Resource not found"`                              |
  | `:service_unavailable`| `"A downstream dependency is unavailable — try..."` |
  | `%Flop.Meta{}`        | `"Invalid filter or sort parameters"`               |
  | anything else         | `"An unexpected error occurred"`                    |

  Tools that need a tailored not-found message (e.g. including the resource id)
  should use `error_response/2` from `EdgeAdminMcp` rather than this module.
  """

  def message(%Ecto.Changeset{} = cs) do
    details =
      Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
      end)

    "Validation failed: #{inspect(details)}"
  end

  def message({:conflict, reason}) when is_binary(reason), do: reason
  def message(:not_found), do: "Resource not found"
  def message(:service_unavailable), do: "A downstream dependency is unavailable — try again shortly"
  def message(%Flop.Meta{}), do: "Invalid filter or sort parameters"
  def message(_), do: "An unexpected error occurred"
end
