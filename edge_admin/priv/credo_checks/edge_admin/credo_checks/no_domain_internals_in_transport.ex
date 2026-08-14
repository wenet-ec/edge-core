# edge_admin/priv/credo_checks/edge_admin/credo_checks/no_domain_internals_in_transport.ex
defmodule EdgeAdmin.CredoChecks.NoDomainInternalsInTransport do
  @moduledoc false

  use Credo.Check,
    id: "EC1002",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Transport entry points should call domain contexts, not compose domain
      internals directly.

      Forms, checks, resources, queries, persistence modules, and workflows are
      owned by the context layer. REST controllers and MCP tools should converge
      on the same context functions.
      """
    ]

  alias Credo.Code.Name

  @transport_paths [
    "lib/edge_admin_web/controllers/",
    "lib/edge_admin_mcp/tools/"
  ]

  @internal_segments ~w(Forms Checks Resources Queries Persistence Workflows)a
  @message "Transport modules must call domain context modules instead of domain internals."

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

  defp walk({:__aliases__, meta, module_parts} = ast, ctx) do
    issue =
      if domain_internal?(module_parts) do
        issue_for(ctx, meta, Name.full(module_parts))
      end

    {ast, put_issue(ctx, issue)}
  end

  defp walk({:alias, _meta, [{{_, _, [{:__aliases__, _opts, base_alias}, :{}]}, _, aliases}]} = ast, ctx) do
    issues =
      Enum.flat_map(aliases, fn {:__aliases__, meta, module} ->
        module_parts = List.flatten([base_alias, module])

        if domain_internal?(module_parts) do
          [issue_for(ctx, meta, Name.full(module))]
        else
          []
        end
      end)

    {ast, put_issue(ctx, issues)}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp domain_internal?([:EdgeAdmin, _domain, segment | _rest]) when segment in @internal_segments, do: true
  defp domain_internal?(_module_parts), do: false

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
