# edge_admin/lib/edge_admin/repo.ex
#
# Three-module design: a dispatcher facade + two real Ecto.Repo impls.
#
#   EdgeAdmin.Repo           Public dispatcher facade. Application code calls
#                            EdgeAdmin.Repo.* and is naive about which adapter
#                            is running. NOT an Ecto.Repo — a thin forwarder
#                            that reads :repo_impl from app env at runtime
#                            and delegates.
#
#   EdgeAdmin.Repo.Postgres  Real Ecto.Repo with the Postgres adapter baked in.
#                            Started in Postgres mode (DB_ADAPTER=postgres).
#                            Hosts the Notifier sub-repo for Oban LISTEN.
#
#   EdgeAdmin.Repo.SQLite    Real Ecto.Repo with the SQLite3 adapter baked in.
#                            Started in SQLite mode (DB_ADAPTER=sqlite).
#
# Both impl modules exist in every binary (no compile-time DB_ADAPTER read).
# At runtime, only the configured impl's pool is started — the other module
# is dormant code. One compiled artifact serves both modes.
#
# Test infrastructure (Sandbox, ExMachina), release tasks (Migrator), and Oban
# take a real Ecto.Repo module — for those, we read :repo_impl (or pass the
# implementation explicitly) and bypass the dispatcher. LiveDashboard discovers
# the running implementation through Ecto.Repo.all_running/0 and supports both
# configured adapters; it does not use this facade as an Ecto.Repo.

defmodule EdgeAdmin.Repo do
  @moduledoc """
  Dispatcher facade. Forwards every callable on `Ecto.Repo` (and the
  functions injected by `Ecto.Adapters.SQL.__before_compile__`) to the
  impl module configured in `:repo_impl` (set in `runtime.exs` from
  `DB_ADAPTER`).

  Comprehensive on purpose: covers the entire `Ecto.Repo` surface so
  application code never has to think about which adapter is active,
  and never needs to extend this module when reaching for a new
  callback.

  What is NOT forwarded — and why:

    * Lifecycle callbacks (`start_link/1`, `stop/1`, `init/2`,
      `child_spec/1`) — the dispatcher is not a real `Ecto.Repo` and
      cannot be supervised. Supervisors must reference the impl
      directly (see `EdgeAdmin.Application.repo_children/0`).
    * `config/0` — adapter/pool configuration is impl-specific.
    * User callback hooks (`prepare_query/3`, `prepare_transaction/2`,
      `default_options/1`) — these are intended to be *overridden* on
      the impl, not invoked through it.

  Anything that genuinely needs the running adapter (Sandbox, Migrator, Oban)
  should reference the implementation module directly via
  `Application.fetch_env!(:edge_admin, :repo_impl)`.
  """

  defp impl, do: Application.fetch_env!(:edge_admin, :repo_impl)

  # Ecto.Repo callbacks for struct/changeset operations.
  @doc "Inserts a struct or changeset using the active repository implementation."
  def insert(struct_or_changeset, opts \\ []), do: impl().insert(struct_or_changeset, opts)
  @doc "Inserts a struct or changeset, raising on failure."
  def insert!(struct_or_changeset, opts \\ []), do: impl().insert!(struct_or_changeset, opts)
  @doc "Updates a changeset using the active repository implementation."
  def update(changeset, opts \\ []), do: impl().update(changeset, opts)
  @doc "Updates a changeset, raising on failure."
  def update!(changeset, opts \\ []), do: impl().update!(changeset, opts)

  @doc "Inserts or updates a changeset according to its action."
  def insert_or_update(changeset, opts \\ []), do: impl().insert_or_update(changeset, opts)

  @doc "Inserts or updates a changeset, raising on failure."
  def insert_or_update!(changeset, opts \\ []), do: impl().insert_or_update!(changeset, opts)

  @doc "Deletes a struct or changeset."
  def delete(struct_or_changeset, opts \\ []), do: impl().delete(struct_or_changeset, opts)

  @doc "Deletes a struct or changeset, raising on failure."
  def delete!(struct_or_changeset, opts \\ []), do: impl().delete!(struct_or_changeset, opts)

  @doc "Inserts multiple entries in one operation."
  def insert_all(schema_or_source, entries_or_query, opts \\ []),
    do: impl().insert_all(schema_or_source, entries_or_query, opts)

  @doc "Loads database values into a schema or typed map."
  def load(schema_or_map, data), do: impl().load(schema_or_map, data)

  @doc "Reloads a struct or list of structs from the database."
  def reload(struct_or_structs, opts \\ []), do: impl().reload(struct_or_structs, opts)

  @doc "Reloads a struct or list of structs, raising when a row is missing."
  def reload!(struct_or_structs, opts \\ []), do: impl().reload!(struct_or_structs, opts)

  # Ecto.Repo.Queryable callbacks.
  @doc "Fetches a record by primary key, returning nil when it is absent."
  def get(queryable, id, opts \\ []), do: impl().get(queryable, id, opts)
  @doc "Fetches a record by primary key, raising when it is absent."
  def get!(queryable, id, opts \\ []), do: impl().get!(queryable, id, opts)
  @doc "Fetches a record by the given clauses."
  def get_by(queryable, clauses, opts \\ []), do: impl().get_by(queryable, clauses, opts)
  @doc "Fetches a record by clauses, raising when it is absent."
  def get_by!(queryable, clauses, opts \\ []), do: impl().get_by!(queryable, clauses, opts)
  @doc "Returns all records matching a queryable."
  def all(queryable, opts \\ []), do: impl().all(queryable, opts)
  @doc "Returns all records matching the given clauses."
  def all_by(queryable, clauses, opts \\ []), do: impl().all_by(queryable, clauses, opts)
  @doc "Streams records from a queryable."
  def stream(queryable, opts \\ []), do: impl().stream(queryable, opts)
  @doc "Returns one record or nil."
  def one(queryable, opts \\ []), do: impl().one(queryable, opts)
  @doc "Returns one record, raising when multiple or no records match."
  def one!(queryable, opts \\ []), do: impl().one!(queryable, opts)
  @doc "Checks whether a queryable has at least one matching record."
  def exists?(queryable, opts \\ []), do: impl().exists?(queryable, opts)
  @doc "Updates all records matching a queryable."
  def update_all(queryable, updates, opts \\ []), do: impl().update_all(queryable, updates, opts)
  @doc "Deletes all records matching a queryable."
  def delete_all(queryable, opts \\ []), do: impl().delete_all(queryable, opts)

  # `aggregate` has /2, /3, and /4 arities. Default-arg declarations can only
  # appear once per name across all arities, so each arity is written out
  # explicitly without defaults.
  @doc "Calculates an aggregate over a queryable."
  def aggregate(queryable, aggregate), do: impl().aggregate(queryable, aggregate)

  @doc "Calculates an aggregate with options or a field argument."
  def aggregate(queryable, aggregate, opts_or_field), do: impl().aggregate(queryable, aggregate, opts_or_field)

  @doc "Calculates an aggregate over a specific field with options."
  def aggregate(queryable, aggregate, field, opts), do: impl().aggregate(queryable, aggregate, field, opts)

  @doc "Preloads associations on a struct or list of structs."
  def preload(structs_or_struct_or_nil, preloads, opts \\ []),
    do: impl().preload(structs_or_struct_or_nil, preloads, opts)

  # Transaction callbacks.
  @doc "Runs a function or Ecto.Multi inside a database transaction."
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

  @doc "Runs a function or Ecto.Multi using Ecto's transaction API."
  def transact(fun_or_multi, opts \\ []), do: impl().transact(fun_or_multi, opts)
  @doc "Returns whether the current process is inside a transaction."
  def in_transaction?, do: impl().in_transaction?()
  @doc "Rolls back the current transaction with the given value."
  def rollback(value), do: impl().rollback(value)

  # Process-local repo and connection checkout callbacks.
  @doc "Returns the active dynamic repository for the current process."
  def get_dynamic_repo, do: impl().get_dynamic_repo()
  @doc "Sets the dynamic repository for the current process."
  def put_dynamic_repo(name_or_pid), do: impl().put_dynamic_repo(name_or_pid)
  @doc "Checks out a database connection for the duration of a function."
  def checkout(fun, opts \\ []), do: impl().checkout(fun, opts)
  @doc "Returns whether the current process has checked out a connection."
  def checked_out?, do: impl().checked_out?()

  # SQL adapter passthroughs injected by Ecto.Adapters.SQL.__before_compile__.
  @doc "Executes a raw SQL query against the active repository."
  def query(sql, params \\ [], opts \\ []), do: impl().query(sql, params, opts)
  @doc "Executes a raw SQL query, raising on failure."
  def query!(sql, params \\ [], opts \\ []), do: impl().query!(sql, params, opts)
  @doc "Executes multiple SQL statements against the active repository."
  def query_many(sql, params \\ [], opts \\ []), do: impl().query_many(sql, params, opts)
  @doc "Executes multiple SQL statements, raising on failure."
  def query_many!(sql, params \\ [], opts \\ []), do: impl().query_many!(sql, params, opts)
  @doc "Builds SQL for an Ecto query without executing it."
  def to_sql(operation, queryable, opts \\ []), do: impl().to_sql(operation, queryable, opts)
  @doc "Explains the query plan for an Ecto query."
  def explain(operation, queryable, opts \\ []), do: impl().explain(operation, queryable, opts)
  @doc "Disconnects idle database connections matching the interval."
  def disconnect_all(interval, opts \\ []), do: impl().disconnect_all(interval, opts)

  @doc "Returns the adapter module used by the active repository implementation."
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
