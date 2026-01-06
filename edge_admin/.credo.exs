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
          # Readability customizations
          {Credo.Check.Readability.MaxLineLength, [priority: :low, max_length: 120]},

          # Refactoring customizations
          # ABC Size measures Assignment, Branch, and Condition complexity
          # Increased from 40 to 50 to accommodate complex business logic functions
          # Consider refactoring functions above this threshold
          {Credo.Check.Refactor.ABCSize, [max_size: 50]},

          # Consistency checks from plugins
          {CredoEnvvar.Check.Warning.EnvironmentVariablesAtCompileTime},
          {CredoNaming.Check.Warning.AvoidSpecificTermsInModuleNames,
           terms: ["Manager", "Fetcher", "Builder", "Persister", "Serializer", ~r/^Helpers?$/i, ~r/^Utils?$/i]},
          {CredoNaming.Check.Consistency.ModuleFilename,
           excluded_paths: ["config", "mix.exs", "priv", "test/support", "lib/edge_admin_web/live"],
           acronyms: []}
        ],
        disabled: [
          # Disable overly strict checks for pragmatic API development
          {Credo.Check.Readability.ModuleDoc, false},
          {Credo.Check.Readability.Specs, false},
          {Credo.Check.Readability.StrictModuleLayout, false},

          # Duplicated code is acceptable in controllers and simple CRUD operations
          {Credo.Check.Design.DuplicatedCode, false}
        ]
      }
    }
  ]
}
