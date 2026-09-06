# edge_admin/lib/edge_admin/schema.ex
defmodule EdgeAdmin.Schema do
  @moduledoc false
  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      use Flop.Schema

      import Ecto.Changeset

      alias Ecto.Schema

      @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true, dump: :raw, type: :uuid}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime]
      @flop_options [filterable: [], sortable: []]
    end
  end
end
