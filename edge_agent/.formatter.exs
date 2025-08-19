# edge_agent/.formatter.exs
[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  subdirectories: ["priv/*/migrations"],
  inputs: ["*.{ex,exs}", "{config,lib,priv,rel,test}/**/*.{ex,exs}"],
  line_length: 120,
  plugins: [Styler]
]
