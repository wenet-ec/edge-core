# edge_admin/lib/edge_admin/config.ex
defmodule EdgeAdmin.Config do
  @moduledoc """
  This modules provides various helpers to handle environment variables
  """

  @type value_type :: :string | :integer | :boolean | :uri | :cors | :list
  @type config_type :: String.t() | integer() | boolean() | URI.t() | [String.t()]

  @spec get_env(String.t(), nil | value_type(), any()) :: config_type()
  def get_env(key, type \\ :string, default \\ nil) do
    value = System.get_env(key)

    case value do
      nil -> default
      _ -> parse_env(value, type)
    end
  end

  @spec get_env!(String.t(), nil | value_type()) :: config_type()
  def get_env!(key, type \\ :string) do
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
    String.split(value, ",") |> Enum.map(&String.trim/1)
  end
end
