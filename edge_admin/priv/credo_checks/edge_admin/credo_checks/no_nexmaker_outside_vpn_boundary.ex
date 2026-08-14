# edge_admin/priv/credo_checks/edge_admin/credo_checks/no_nexmaker_outside_vpn_boundary.ex
defmodule EdgeAdmin.CredoChecks.NoNexmakerOutsideVpnBoundary do
  @moduledoc false

  use Credo.Check,
    id: "EC1004",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Admin application code should keep direct Nexmaker usage at the VPN boundary.

      Other domains should call `EdgeAdmin.Vpn` instead of depending on
      Netmaker API or netclient CLI details.
      """
    ]

  alias Credo.Code.Name

  @admin_app_path "lib/edge_admin/"
  @allowed_paths [
    "lib/edge_admin/vpn/"
  ]

  @message "Direct `Nexmaker` usage is only allowed at the Admin VPN boundary. Call `EdgeAdmin.Vpn` instead."

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    if admin_app_file?(source_file.filename) and not allowed_file?(source_file.filename) do
      ctx = Context.build(source_file, params, __MODULE__)
      result = Credo.Code.prewalk(source_file, &walk/2, ctx)

      result.issues
    else
      []
    end
  end

  defp walk({:__aliases__, meta, module_parts} = ast, ctx) do
    issue =
      if nexmaker_module?(module_parts) do
        issue_for(ctx, meta, Name.full(module_parts))
      end

    {ast, put_issue(ctx, issue)}
  end

  defp walk({:alias, _meta, [{{_, _, [{:__aliases__, _opts, base_alias}, :{}]}, _, aliases}]} = ast, ctx) do
    issues =
      Enum.flat_map(aliases, fn {:__aliases__, meta, module} ->
        module_parts = List.flatten([base_alias, module])

        if nexmaker_module?(module_parts) do
          [issue_for(ctx, meta, Name.full(module))]
        else
          []
        end
      end)

    {ast, put_issue(ctx, issues)}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp nexmaker_module?([:Nexmaker | _rest]), do: true
  defp nexmaker_module?(_module_parts), do: false

  defp issue_for(ctx, meta, trigger) do
    format_issue(
      ctx,
      message: @message,
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp admin_app_file?(filename), do: path_matches?(filename, @admin_app_path)
  defp allowed_file?(filename), do: Enum.any?(@allowed_paths, &path_matches?(filename, &1))

  defp path_matches?(filename, path) do
    filename = String.replace(filename, "\\", "/")

    String.starts_with?(filename, path) or String.contains?(filename, "/" <> path)
  end
end
