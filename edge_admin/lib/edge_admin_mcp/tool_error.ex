# edge_admin/lib/edge_admin_mcp/tool_error.ex
defmodule EdgeAdminMcp.ToolError do
  @moduledoc """
  Builds structured error maps for MCP tool responses.

  | Value                 | `error` field        | Notes                        |
  |-----------------------|----------------------|------------------------------|
  | `%Ecto.Changeset{}`   | `validation_failed`  | includes `details` map       |
  | `{:conflict, reason}` | `conflict`           | reason string in `message`   |
  | `:not_found`          | `not_found`          | use 2-arity for resource name|
  | `:service_unavailable`| `service_unavailable`|                              |
  | `%Flop.Meta{}`        | `bad_request`        | invalid filter/sort params   |
  | anything else         | `internal_error`     |                              |
  """

  def build(%Ecto.Changeset{} = cs) do
    details =
      Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {k, v}, acc ->
          String.replace(acc, "%{#{k}}", to_string(v))
        end)
      end)

    %{error: "validation_failed", message: "Validation failed", details: details}
  end

  def build({:conflict, reason}) when is_binary(reason) do
    %{error: "conflict", message: reason}
  end

  def build(:not_found) do
    %{error: "not_found", message: "Resource not found"}
  end

  def build(:service_unavailable) do
    %{error: "service_unavailable", message: "A downstream dependency is unavailable — try again shortly"}
  end

  def build(%Flop.Meta{}) do
    %{error: "bad_request", message: "Invalid filter or sort parameters"}
  end

  def build(_) do
    %{error: "internal_error", message: "An unexpected error occurred"}
  end

  def build(:not_found, message) when is_binary(message) do
    %{error: "not_found", message: message}
  end
end
