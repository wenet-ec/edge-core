# edge_agent/priv/credo_checks/edge_agent/credo_checks/no_repo_in_transport.ex
defmodule EdgeAgent.CredoChecks.NoRepoInTransport do
  @moduledoc false

  use Credo.Check,
    id: "EC2001",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Transport entry points should not reach into the database directly.

      Controllers should call the domain context. The context owns the
      validation and persistence pipeline.
      """
    ]

  alias Credo.Code.Name

  @transport_paths [
    "lib/edge_agent_web/controllers/"
  ]

  @message "Transport modules must not call `EdgeAgent.Repo` directly. Call the domain context instead."

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
      if Name.full(module_parts) == "EdgeAgent.Repo" do
        issue_for(ctx, meta, "EdgeAgent.Repo")
      end

    {ast, put_issue(ctx, issue)}
  end

  defp walk({:alias, _meta, [{{_, _, [{:__aliases__, _opts, base_alias}, :{}]}, _, aliases}]} = ast, ctx) do
    issues =
      Enum.flat_map(aliases, fn {:__aliases__, meta, module} ->
        full_module = Name.full([base_alias, module])

        if full_module == "EdgeAgent.Repo" do
          [issue_for(ctx, meta, "Repo")]
        else
          []
        end
      end)

    {ast, put_issue(ctx, issues)}
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
