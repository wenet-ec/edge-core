# edge_admin/lib/edge_admin/sort.ex
defmodule EdgeAdmin.Sort do
  @moduledoc false

  @pattern "^-?[A-Za-z][A-Za-z0-9_]*(,-?[A-Za-z][A-Za-z0-9_]*)*$"
  @regex ~r/^-?[A-Za-z][A-Za-z0-9_]*(,-?[A-Za-z][A-Za-z0-9_]*)*$/

  @spec pattern() :: String.t()
  def pattern, do: @pattern

  @spec regex() :: Regex.t()
  def regex, do: @regex

  @spec parse(String.t()) ::
          {:ok, %{order_by: [String.t()], order_directions: [:asc | :desc]}} | {:error, :invalid_sort}
  def parse(sort) when is_binary(sort) do
    if Regex.match?(@regex, sort) do
      {order_by, order_directions} =
        sort
        |> String.split(",")
        |> Enum.map(fn
          <<"-", field::binary>> -> {field, :desc}
          field -> {field, :asc}
        end)
        |> Enum.unzip()

      {:ok, %{order_by: order_by, order_directions: order_directions}}
    else
      {:error, :invalid_sort}
    end
  end
end
