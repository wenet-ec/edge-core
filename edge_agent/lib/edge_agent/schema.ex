# edge_agent/lib/edge_agent/schema.ex
defmodule EdgeAgent.Schema do
  @moduledoc false
  defmacro __using__(_) do
    quote do
      use Ecto.Schema

      import Ecto.Changeset

      alias Ecto.Schema

      @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime]
    end
  end
end
