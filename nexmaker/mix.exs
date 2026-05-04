# nexmaker/mix.exs
defmodule Nexmaker.MixProject do
  use Mix.Project

  def project do
    [
      app: :nexmaker,
      version: "1.5.1",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package()
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{},
      files: ~w(lib mix.exs LICENSE NOTICE README.md)
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"}
    ]
  end
end
