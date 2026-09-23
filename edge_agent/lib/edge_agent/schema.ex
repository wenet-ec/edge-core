# edge_agent/lib/edge_agent/schema.ex
defmodule EdgeAgent.Schema do
  @moduledoc """
  Shared Ecto schema defaults for Agent persistence models.

  Models use UUIDv7 binary IDs, binary foreign keys, and UTC timestamps.
  """
  defmacro __using__(_) do
    quote do
      use Ecto.Schema

      import Ecto.Changeset

      alias Ecto.Schema

      @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true, dump: :raw, type: :uuid}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime]
    end
  end
end
