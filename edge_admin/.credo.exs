# edge_admin/.credo.exs
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["*.exs", "lib/", "priv/", "config/", "rel/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      plugins: [],
      requires: [],
      strict: true,
      parse_timeout: 5000,
      color: true,
      checks: %{
        enabled: [
          # Use modern Credo defaults with specific customizations
          {Credo.Check.Readability.MaxLineLength, [priority: :low, max_length: 120]},
          {Credo.Check.Refactor.ABCSize, [max_size: 40]},

          # Keep valuable naming checks
          {CredoNaming.Check.Warning.AvoidSpecificTermsInModuleNames,
           terms: ["Manager", "Fetcher", "Builder", "Persister", "Serializer", ~r/^Helpers?$/i, ~r/^Utils?$/i]},
          {CredoNaming.Check.Consistency.ModuleFilename,
           excluded_paths: ["config", "mix.exs", "priv", "test/support"], acronyms: []},

          # Keep database migration safety
          {ExcellentMigrations.CredoCheck.MigrationsSafety, []}
        ],
        disabled: [
          # Disable overly strict checks for API development
          {Credo.Check.Readability.ModuleDoc, false},
          {Credo.Check.Readability.Specs, false},
          {Credo.Check.Readability.StrictModuleLayout, false},
          {Credo.Check.Design.DuplicatedCode, false},
          {CredoEnvvar.Check.Warning.EnvironmentVariablesAtCompileTime, false}
        ]
      }
    }
  ]
}
