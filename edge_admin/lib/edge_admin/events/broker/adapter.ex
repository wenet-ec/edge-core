# edge_admin/lib/edge_admin/events/broker/adapter.ex
defmodule EdgeAdmin.Events.Broker.Adapter do
  @moduledoc """
  Behaviour that all event broker adapters must implement.

  An adapter receives a fully-built envelope map and is responsible
  for serialising and publishing it to the underlying broker.

  ## Adding a new adapter

    1. Implement the `Adapter` behaviour in `broker/adapters/your_adapter.ex`.
    2. Add an entry to `EdgeAdmin.Events.Broker.AdapterRegistry`.
    3. Add a `build_children/1` clause in `broker/supervisor.ex` for the
       adapter's supervised processes (this stays per-adapter because the
       supervision shape is genuinely heterogeneous).
    4. Add the per-adapter env-var parsing block in `config/runtime.exs`.

  Broker delivery routing and the rejection error in `runtime.exs` pick up
  the new adapter automatically.
  """

  @doc """
  Publishes a pre-built event envelope to the broker.

  The envelope is already serialisable — all values are strings, numbers,
  or nested maps. Adapters should JSON-encode and publish it.

  Returns `:ok` on success or `{:error, reason}` on failure.
  The caller (`EdgeAdmin.Events.Broker.publish_envelope/1`) logs the error;
  adapters do not need to.
  """
  @callback publish(envelope :: map()) :: :ok | {:error, term()}

  @doc """
  Returns `:ok` if the adapter has an active connection to the broker,
  or `{:error, reason}` if not connected or the broker is unreachable.
  """
  @callback healthy?() :: :ok | {:error, String.t()}
end
