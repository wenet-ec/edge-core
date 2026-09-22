# edge_admin/lib/edge_admin/repo.ex
defmodule EdgeAdmin.Repo do
  @moduledoc """
  Dispatcher facade. Forwards every callable on `Ecto.Repo` (and the
  functions injected by `Ecto.Adapters.SQL.__before_compile__`) to the
  implementation configured at runtime.

  Comprehensive on purpose: covers the entire `Ecto.Repo` surface so
  application code never has to think about which adapter is active,
  and never needs to extend this module when reaching for a new
  callback.

  What is NOT forwarded — and why:

    * Lifecycle callbacks (`start_link/1`, `stop/1`, `init/2`,
      `child_spec/1`) — the dispatcher is not a real `Ecto.Repo` and
      cannot be supervised. Supervisors must reference the impl
      directly from the supervision configuration.
    * `config/0` — adapter/pool configuration is impl-specific.
    * User callback hooks (`prepare_query/3`, `prepare_transaction/2`,
      `default_options/1`) — these are intended to be *overridden* on
      the impl, not invoked through it.

  Anything that genuinely needs the running adapter (Sandbox, Migrator, Oban)
  should reference the configured implementation directly.
  """

  defp impl, do: Application.fetch_env!(:edge_admin, :repo_impl)

  # Ecto.Repo callbacks for struct/changeset operations.
  def insert(struct_or_changeset, opts \\ []), do: impl().insert(struct_or_changeset, opts)
  def insert!(struct_or_changeset, opts \\ []), do: impl().insert!(struct_or_changeset, opts)
  def update(changeset, opts \\ []), do: impl().update(changeset, opts)
  def update!(changeset, opts \\ []), do: impl().update!(changeset, opts)

  def insert_or_update(changeset, opts \\ []), do: impl().insert_or_update(changeset, opts)

  def insert_or_update!(changeset, opts \\ []), do: impl().insert_or_update!(changeset, opts)

  def delete(struct_or_changeset, opts \\ []), do: impl().delete(struct_or_changeset, opts)

  def delete!(struct_or_changeset, opts \\ []), do: impl().delete!(struct_or_changeset, opts)

  def insert_all(schema_or_source, entries_or_query, opts \\ []),
    do: impl().insert_all(schema_or_source, entries_or_query, opts)

  def load(schema_or_map, data), do: impl().load(schema_or_map, data)

  def reload(struct_or_structs, opts \\ []), do: impl().reload(struct_or_structs, opts)

  def reload!(struct_or_structs, opts \\ []), do: impl().reload!(struct_or_structs, opts)

  # Ecto.Repo.Queryable callbacks.
  def get(queryable, id, opts \\ []), do: impl().get(queryable, id, opts)
  def get!(queryable, id, opts \\ []), do: impl().get!(queryable, id, opts)
  def get_by(queryable, clauses, opts \\ []), do: impl().get_by(queryable, clauses, opts)
  def get_by!(queryable, clauses, opts \\ []), do: impl().get_by!(queryable, clauses, opts)
  def all(queryable, opts \\ []), do: impl().all(queryable, opts)
  def all_by(queryable, clauses, opts \\ []), do: impl().all_by(queryable, clauses, opts)
  def stream(queryable, opts \\ []), do: impl().stream(queryable, opts)
  def one(queryable, opts \\ []), do: impl().one(queryable, opts)
  def one!(queryable, opts \\ []), do: impl().one!(queryable, opts)
  def exists?(queryable, opts \\ []), do: impl().exists?(queryable, opts)
  def update_all(queryable, updates, opts \\ []), do: impl().update_all(queryable, updates, opts)
  def delete_all(queryable, opts \\ []), do: impl().delete_all(queryable, opts)

  # `aggregate` has /2, /3, and /4 arities. Default-arg declarations can only
  # appear once per name across all arities, so each arity is written out
  # explicitly without defaults.
  def aggregate(queryable, aggregate), do: impl().aggregate(queryable, aggregate)

  def aggregate(queryable, aggregate, opts_or_field), do: impl().aggregate(queryable, aggregate, opts_or_field)

  def aggregate(queryable, aggregate, field, opts), do: impl().aggregate(queryable, aggregate, field, opts)

  def preload(structs_or_struct_or_nil, preloads, opts \\ []),
    do: impl().preload(structs_or_struct_or_nil, preloads, opts)

  # Transaction callbacks.
  def transaction(fun_or_multi, opts \\ []), do: impl().transaction(fun_or_multi, opts)
  @doc "Runs a transaction with the adapter-specific write-lock behavior."
  def transaction_with_write_lock(fun_or_multi) do
    opts =
      case __adapter__() do
        Ecto.Adapters.SQLite3 -> [mode: :immediate]
        _ -> []
      end

    transaction(fun_or_multi, opts)
  end

  def transact(fun_or_multi, opts \\ []), do: impl().transact(fun_or_multi, opts)
  def in_transaction?, do: impl().in_transaction?()
  def rollback(value), do: impl().rollback(value)

  # Process-local repo and connection checkout callbacks.
  def get_dynamic_repo, do: impl().get_dynamic_repo()
  def put_dynamic_repo(name_or_pid), do: impl().put_dynamic_repo(name_or_pid)
  def checkout(fun, opts \\ []), do: impl().checkout(fun, opts)
  def checked_out?, do: impl().checked_out?()

  # SQL adapter passthroughs injected by Ecto.Adapters.SQL.__before_compile__.
  def query(sql, params \\ [], opts \\ []), do: impl().query(sql, params, opts)
  def query!(sql, params \\ [], opts \\ []), do: impl().query!(sql, params, opts)
  def query_many(sql, params \\ [], opts \\ []), do: impl().query_many(sql, params, opts)
  def query_many!(sql, params \\ [], opts \\ []), do: impl().query_many!(sql, params, opts)
  def to_sql(operation, queryable, opts \\ []), do: impl().to_sql(operation, queryable, opts)
  def explain(operation, queryable, opts \\ []), do: impl().explain(operation, queryable, opts)
  def disconnect_all(interval, opts \\ []), do: impl().disconnect_all(interval, opts)

  def __adapter__, do: impl().__adapter__()

  @doc """
  Translates a unique constraint violation on the given fields into `{:error, {:conflict, reason}}`.
  All other changeset errors pass through as `{:error, changeset}` for a 422 response.

  Call this after `Repo.insert/2` anywhere a unique index collision should be a 409
  rather than a validation error. The first matching field determines the reason message.
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

defmodule EdgeAdmin.Repo.Postgres do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :edge_admin,
    adapter: Ecto.Adapters.Postgres,
    telemetry_prefix: [:edge_admin, :repo]

  @doc """
  Dynamically loads the repository url from the
  DATABASE_URL environment variable.
  """
  def init(_, opts) do
    {:ok, Keyword.put(opts, :url, Application.get_env(:edge_admin, __MODULE__)[:url])}
  end

  defmodule Notifier do
    # Dedicated repo used only by Oban.Notifiers.Postgres to hold the long-lived
    # LISTEN connection. Bypasses PgBouncer (transaction-mode pooling kills
    # session-pinned LISTEN), pointing straight at the primary. Pool size 2
    # is enough — Oban opens one notification connection.
    @moduledoc false
    use Ecto.Repo,
      adapter: Ecto.Adapters.Postgres,
      otp_app: :edge_admin,
      telemetry_prefix: [:edge_admin, :repo_notifier]
  end
end

defmodule EdgeAdmin.Repo.SQLite do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :edge_admin,
    adapter: Ecto.Adapters.SQLite3,
    telemetry_prefix: [:edge_admin, :repo]

  def init(_, opts), do: {:ok, opts}
end
