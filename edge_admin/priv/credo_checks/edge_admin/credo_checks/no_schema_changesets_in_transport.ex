# edge_admin/priv/credo_checks/edge_admin/credo_checks/no_schema_changesets_in_transport.ex
defmodule EdgeAdmin.CredoChecks.NoSchemaChangesetsInTransport do
  @moduledoc false

  use Credo.Check,
    id: "EC1003",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Transport entry points should not run changesets directly.

      Controllers and MCP tools should call the domain context. The context owns
      the Form -> Checks -> Resource/Persistence -> Schema changeset -> DB
      constraint pipeline.
      """
    ]

  alias Credo.Code.Name

  @transport_paths [
    "lib/edge_admin_web/controllers/",
    "lib/edge_admin_mcp/tools/"
  ]

  @changeset_functions [:changeset, :create_changeset, :update_changeset, :delete_changeset]
  @message "Transport modules must not call changesets directly. Call the domain context instead."

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    if transport_file?(source_file.filename) do
      ctx = Context.build(source_file, params, __MODULE__)
      result = Credo.Code.prewalk(source_file, &walk/2, ctx)

      result.issues
    else
      []
    end
  end

  defp walk({{:., meta, [{:__aliases__, _alias_meta, module_parts}, function]}, _call_meta, _args} = ast, ctx)
       when function in @changeset_functions do
    issue =
      issue_for(ctx, meta, "#{Name.full(module_parts)}.#{function}")

    {ast, put_issue(ctx, issue)}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp issue_for(ctx, meta, trigger) do
    format_issue(
      ctx,
      message: @message,
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp transport_file?(filename) do
    filename = String.replace(filename, "\\", "/")

    Enum.any?(@transport_paths, fn path ->
      String.starts_with?(filename, path) or String.contains?(filename, "/" <> path)
    end)
  end
end
