# .formatter.exs
[
  import_deps: [:ecto, :ecto_sql, :phoenix, :open_api_spex],
  subdirectories: ["priv/*/migrations"],
  inputs: ["*.{ex,exs}", "{config,lib,priv,rel,test}/**/*.{ex,exs}"],
  line_length: 180,
  plugins: [Styler]
]
