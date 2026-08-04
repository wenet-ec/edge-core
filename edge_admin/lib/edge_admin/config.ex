# edge_admin/lib/edge_admin/config.ex
defmodule EdgeAdmin.Config do
  @moduledoc """
  Helpers for reading and parsing environment variables in `runtime.exs`.

  Two readers (`get_env/3` with default, `get_env!/2` raising on missing) plus
  a value-type system that coerces the raw string into the right Elixir term:
  `:string | :integer | :boolean | :uri | :cors | :list | :atom | :positive_integer`.

  """

  @type value_type :: :string | :integer | :boolean | :uri | :cors | :list | :atom | :positive_integer
  @type config_type :: String.t() | integer() | boolean() | URI.t() | [String.t()] | atom()

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

  @doc """
  Reads an optional comma-separated list of absolute HTTP(S) URLs.

  Empty entries are discarded. Raises during boot for malformed values so a
  bad deployment configuration cannot be advertised to enrolling agents.
  """
  @spec get_http_url_list(String.t(), [String.t()]) :: [String.t()]
  def get_http_url_list(key, default \\ []) do
    key
    |> get_env(:list, default)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn url ->
      uri = URI.parse(url)

      if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" do
        url
      else
        raise "Invalid #{key} entry #{inspect(url)} — expected a full http:// or https:// URL"
      end
    end)
  end

  defp parse_env(value, :string), do: value
  defp parse_env(value, :integer), do: String.to_integer(value)

  defp parse_env("", :boolean), do: false
  defp parse_env(value, :boolean), do: String.downcase(value) in ~w(true 1)

  defp parse_env(value, :cors) when is_bitstring(value) do
    case String.split(value, ",") do
      [origin] -> origin
      origins -> origins
    end
  end

  defp parse_env("", :uri), do: nil
  defp parse_env(value, :uri), do: URI.parse(value)

  defp parse_env("", :list), do: []

  defp parse_env(value, :list) when is_bitstring(value) do
    value |> String.split(",") |> Enum.map(&String.trim/1)
  end

  defp parse_env(value, :atom) when is_bitstring(value) do
    String.to_atom(value)
  end

  defp parse_env(value, :positive_integer) do
    int = String.to_integer(value)

    if int <= 0 do
      raise ArgumentError, "expected positive integer, got: #{int}"
    end

    int
  end
end
