# edge_agent/lib/edge_agent/repo.ex
defmodule EdgeAgent.Repo do
  use Ecto.Repo,
    adapter: Ecto.Adapters.SQLite3,
    otp_app: :edge_agent

  @doc """
  Translates a unique constraint violation on the given fields into `{:error, {:conflict, reason}}`.
  All other changeset errors pass through as `{:error, changeset}` for a 422 response.
  """
  @spec normalize_conflict(
          {:ok, struct()} | {:error, Ecto.Changeset.t()},
          [atom()]
        ) :: {:ok, struct()} | {:error, {:conflict, String.t()}} | {:error, Ecto.Changeset.t()}
  def normalize_conflict({:ok, _} = result, _fields), do: result

  def normalize_conflict({:error, %Ecto.Changeset{} = changeset}, fields) do
    conflicting_field =
      Enum.find(fields, fn field ->
        case Keyword.get(changeset.errors, field) do
          {_, opts} when is_list(opts) -> Keyword.get(opts, :constraint) == :unique
          _ -> false
        end
      end)

    case conflicting_field do
      nil -> {:error, changeset}
      field -> {:error, {:conflict, "#{field} has already been taken"}}
    end
  end
end
