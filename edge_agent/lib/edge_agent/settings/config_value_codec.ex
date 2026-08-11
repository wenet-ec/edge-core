# edge_agent/lib/edge_agent/settings/config_value_codec.ex
defmodule EdgeAgent.Settings.ConfigValueCodec do
  @moduledoc "Pure codecs for structured values stored in Agent settings."

  @doc "Decodes a persisted JSON string list, returning an empty list on invalid input."
  @spec decode_string_list(String.t() | nil) :: list()
  def decode_string_list(nil), do: []

  def decode_string_list(json) when is_binary(json) do
    case JSON.decode(json) do
      {:ok, values} when is_list(values) -> values
      _ -> []
    end
  end

  def decode_string_list(_), do: []

  @doc "Encodes a list for storage in a settings value."
  @spec encode_string_list(list()) :: String.t()
  def encode_string_list(values) when is_list(values), do: JSON.encode!(values)

  @doc "Prepends new non-empty values while preserving incoming and existing order."
  @spec prepend_new_strings([term()], [term()]) :: [term()]
  def prepend_new_strings(incoming, existing) do
    incoming
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
    |> Enum.reject(&(&1 in existing))
    |> Kernel.++(existing)
  end

  @doc "Parses an ISO 8601 datetime, returning nil for missing or invalid values."
  @spec decode_datetime(String.t() | nil) :: DateTime.t() | nil
  def decode_datetime(nil), do: nil

  def decode_datetime(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  def decode_datetime(_), do: nil

  @doc "Formats a datetime for storage in a settings value."
  @spec encode_datetime(DateTime.t()) :: String.t()
  def encode_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
