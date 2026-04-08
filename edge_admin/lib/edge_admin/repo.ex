# edge_admin/lib/edge_admin/repo.ex
defmodule EdgeAdmin.Repo do
  use Ecto.Repo,
    adapter: Ecto.Adapters.Postgres,
    otp_app: :edge_admin,
    telemetry_prefix: [:edge_admin, :repo]

  @doc """
  Dynamically loads the repository url from the
  DATABASE_URL environment variable.
  """
  def init(_, opts) do
    {:ok, Keyword.put(opts, :url, Application.get_env(:edge_admin, __MODULE__)[:url])}
  end

  @doc """
  Translates a unique constraint violation on the given fields into `{:error, {:conflict, reason}}`.
  All other changeset errors pass through as `{:error, changeset}` for a 422 response.

  Call this after `Repo.insert/2` anywhere a unique index collision should be a 409
  rather than a validation error. The first matching field determines the reason message.

  ## Examples

      Repo.insert(changeset) |> Repo.normalize_conflict([:name])
      Repo.insert(changeset) |> Repo.normalize_conflict([:name, :cluster_id])
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
