# edge_admin/priv/credo_checks/edge_admin/credo_checks/abc_size.ex
defmodule EdgeAdmin.CredoChecks.ABCSize do
  @moduledoc false

  use Credo.Check,
    id: "EC2001",
    tags: [:controversial],
    param_defaults: [max_size: 30, excluded_functions: []],
    explanations: [
      check: "Checks ABC complexity while excluding historical migration files.",
      params: [
        max_size: "The maximum ABC size a function should have.",
        excluded_functions: "All listed function calls will be ignored."
      ]
    ]

  @migration_path "/priv/repo/migrations/"

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    if migration_file?(source_file.filename) do
      []
    else
      Credo.Check.Refactor.ABCSize.run(source_file, params)
    end
  end

  defp migration_file?(filename) do
    filename = String.replace(filename, "\\", "/")

    String.starts_with?(filename, "priv/repo/migrations/") or
      String.contains?(filename, @migration_path)
  end
end
