# edge_agent/lib/edge_agent/config.ex
defmodule EdgeAgent.Config do
  @moduledoc """
  Environment-variable readers used by `runtime.exs` to populate
  `:edge_agent` application config.

  Two reader pairs:

  - `get_env/1`, `get_env/2`, `get_env/3` — soft read; missing var yields
    `nil` (no default), the supplied `default`, or a type-specific empty
    value depending on arity and `type`.
  - `get_env!/1`, `get_env!/2` — strict read; raises if the var is unset.

  ## Value-type system

  The `type` argument selects parsing:

  - `:string` — passthrough (returns `nil` if unset)
  - `:integer` — `String.to_integer/1`; **raises if unset**, so always
    pass a default with `get_env/3` or use `get_env!/2`
  - `:boolean` — `nil` and `""` → `false`; otherwise truthy if value (case
    insensitive) is `"true"` or `"1"`
  - `:uri` — `nil`/`""` → `nil`; otherwise `URI.parse/1`
  - `:cors` — `nil` → `nil`; single token returns string, multiple
    comma-separated tokens return a list
  - `:list` — `nil`/`""` → `[]`; otherwise comma-split with trimmed entries
  """

  @type value_type :: :string | :integer | :boolean | :uri | :cors | :list
  @type config_type ::
          String.t() | integer() | boolean() | URI.t() | [String.t()] | nil

  @spec get_env(String.t()) :: config_type()
  def get_env(key) do
    get_env(key, :string)
  end

  @spec get_env(String.t(), value_type()) :: config_type()
  def get_env(key, type) do
    value = System.get_env(key)
    parse_env(value, type)
  end

  @spec get_env(String.t(), value_type(), default) :: config_type() | default
        when default: any()
  def get_env(key, type, default) do
    case System.get_env(key) do
      nil -> default
      value -> parse_env(value, type)
    end
  end

  @spec get_env!(String.t()) :: config_type()
  def get_env!(key) do
    get_env!(key, :string)
  end

  @spec get_env!(String.t(), value_type()) :: config_type()
  def get_env!(key, type) do
    value = System.fetch_env!(key)
    parse_env(value, type)
  end

  defp parse_env(value, :string), do: value
  defp parse_env(value, :integer), do: String.to_integer(value)

  defp parse_env(nil, :boolean), do: false
  defp parse_env("", :boolean), do: false
  defp parse_env(value, :boolean), do: String.downcase(value) in ~w(true 1)

  defp parse_env(nil, :cors), do: nil

  defp parse_env(value, :cors) when is_bitstring(value) do
    case String.split(value, ",") do
      [origin] -> origin
      origins -> origins
    end
  end

  defp parse_env(nil, :uri), do: nil
  defp parse_env("", :uri), do: nil
  defp parse_env(value, :uri), do: URI.parse(value)

  defp parse_env(nil, :list), do: []
  defp parse_env("", :list), do: []

  defp parse_env(value, :list) when is_bitstring(value) do
    value |> String.split(",") |> Enum.map(&String.trim/1)
  end
end
