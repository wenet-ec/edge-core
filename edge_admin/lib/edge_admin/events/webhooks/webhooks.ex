# edge_admin/lib/edge_admin/events/webhooks/webhooks.ex
defmodule EdgeAdmin.Events.Webhooks do
  @moduledoc """
  The Webhooks context — webhook delivery channel for the event publish path.

  Webhooks are user-configured HTTP endpoints that receive a POST per matching
  event. Subscriptions are persisted in the `webhooks` table with field-level
  encryption for `secret` and `headers` via Cloak. Delivery is asynchronous
  through Oban; each event is retried up to `WEBHOOK_MAX_ATTEMPTS` (default 3)
  and then dropped.

  ## Key Concepts

  - **Webhook**: A `(url, secret, headers, event_filters)` tuple persisted as
    a row in the `webhooks` table. `secret` and `headers` are encrypted at
    rest. **Webhooks are immutable after create** — there is no update
    endpoint. To change anything, delete and recreate.
  - **Event filter**: A wildcard pattern matched against an envelope's
    `type` field (`*` matches any sequence of characters, including dots).
  - **Fan-out**: At publish time, the events context calls `fan_out/1` which
    enqueues one Oban job per matching webhook with `WEBHOOK_MAX_ATTEMPTS` as
    the per-job retry budget.
  - **Delivery**: An Oban worker dequeues each job and calls `deliver_event/2`,
    which signs the body, makes the HTTP call, and classifies the response.
    Retry budgeting is Oban's responsibility — the worker just signals the
    outcome via `:ok` / `{:error, _}` / `{:cancel, _}`.

  ## Architecture

  ### Publish path
  1. Business logic calls `EdgeAdmin.Events.publish/1` with a typed event
  2. Events builds a CloudEvents envelope and calls `Webhooks.fan_out/1`
  3. `fan_out/1` queries webhooks whose filters match the envelope's `type`
     and inserts one `DeliverEventWorker` job per match, with `max_attempts`
     read from `WEBHOOK_MAX_ATTEMPTS`
  4. Each worker invocation calls `deliver_event/2` which performs the HTTP
     POST and returns the outcome to Oban

  ### Failure handling
  - **Recoverable** (HTTP 408/429/503, network errors): worker returns
    `{:error, reason}`; Oban schedules a retry with exponential backoff until
    the job's `max_attempts` budget is exhausted, then discards
  - **Terminal** (other HTTP errors): worker returns `{:cancel, reason}`;
    Oban skips remaining retries
  - **Successful**: 2xx response, worker returns `:ok`

  ## Examples

      # Create a webhook
      iex> create_webhook(%{
      ...>   "url" => "https://example.com/hook",
      ...>   "secret" => "a-32-byte-shared-secret-string!!",
      ...>   "event_filters" => ["edge.node.*", "edge.command_execution.completed"]
      ...> })
      {:ok, %Webhook{}}

      # List webhooks matching an event type
      iex> list_webhooks(%{"event_type" => "edge.node.registered"})
      {:ok, {[%Webhook{}, ...], %Flop.Meta{}}}

      # Fan out an envelope to all matching webhooks (called on every publish)
      iex> fan_out(envelope)
      :ok
  """

  import Ecto.Query, warn: false
  import EdgeAdmin.Query, only: [case_insensitive_like: 2]

  alias Ecto.Query.CastError
  alias EdgeAdmin.Events.Webhooks.Delivery
  alias EdgeAdmin.Events.Webhooks.Filter
  alias EdgeAdmin.Events.Webhooks.Forms
  alias EdgeAdmin.Events.Webhooks.Schemas.Webhook
  alias EdgeAdmin.Events.Webhooks.Workers.DeliverEventWorker
  alias EdgeAdmin.Repo

  require Logger

  @doc """
  Lists webhooks with filtering, sorting, and pagination via Flop.

  Supports a custom `event_type` filter that returns only webhooks whose
  stored `event_filters` would match the given concrete event type — same
  semantics as `fan_out/1`'s per-publish dispatch. Applied as an
  Elixir-side post-filter on each fetched page, after Flop's pagination,
  because the wildcard match is not expressible cleanly in SQL across both
  adapters. Pages can therefore return fewer than `page_size` results;
  `meta.has_next_page?` still reflects the underlying scan.

  ## Returns
  - `{:ok, {webhooks, meta}}` - Page of webhooks with Flop.Meta pagination info
  - `{:error, meta}` - Validation errors
  """
  @spec list_webhooks(map()) ::
          {:ok, {[Webhook.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_webhooks(params \\ %{}) do
    flop_params = EdgeAdmin.RequestParser.parse(params)

    {event_type_filters, other_filters} =
      Enum.split_with(flop_params.filters || [], &(&1.field == :event_type))

    flop_params = Map.put(flop_params, :filters, other_filters)

    {ilike_filters, flop_params} =
      EdgeAdmin.RequestParser.split_ilike_filters(flop_params, [:url])

    query =
      Enum.reduce(ilike_filters, Webhook, fn %{field: field, value: value}, acc ->
        from(w in acc, where: case_insensitive_like(field(w, ^field), ^value))
      end)

    case Flop.validate_and_run(query, flop_params,
           for: Webhook,
           replace_invalid_params: true
         ) do
      {:ok, {webhooks, meta}} ->
        {:ok, {filter_by_event_type(webhooks, event_type_filters), meta}}

      {:error, meta} ->
        {:error, meta}
    end
  end

  defp filter_by_event_type(webhooks, []), do: webhooks

  defp filter_by_event_type(webhooks, [%{value: event_type} | _]) do
    Enum.filter(webhooks, fn webhook ->
      Enum.any?(webhook.event_filters, &Filter.matches?(&1, event_type))
    end)
  end

  @doc """
  Gets a single webhook by ID.

  ## Returns
  - `{:ok, webhook}` - Webhook found
  - `{:error, :not_found}` - Webhook doesn't exist or invalid UUID
  """
  @spec get_webhook(String.t()) :: {:ok, Webhook.t()} | {:error, :not_found}
  def get_webhook(id) do
    case Repo.get(Webhook, id) do
      nil -> {:error, :not_found}
      webhook -> {:ok, webhook}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @doc """
  Creates a webhook.

  Validates input via `Forms.CreateWebhookForm`, then inserts via the schema
  changeset. Webhooks are immutable after create; mutate via delete + recreate.

  ## Returns
  - `{:ok, webhook}` - Webhook created successfully
  - `{:error, changeset}` - Validation failed (form-level or schema-level)
  """
  @spec create_webhook(map()) :: {:ok, Webhook.t()} | {:error, Ecto.Changeset.t()}
  def create_webhook(attrs \\ %{}) do
    with {:ok, validated_attrs} <- Forms.CreateWebhookForm.changeset(attrs) do
      %Webhook{}
      |> Webhook.changeset(validated_attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Deletes a webhook.

  ## Returns
  - `{:ok, webhook}` - Deletion succeeded
  - `{:error, changeset}` - Deletion blocked by a constraint
  """
  @spec delete_webhook(Webhook.t()) :: {:ok, Webhook.t()} | {:error, Ecto.Changeset.t()}
  def delete_webhook(%Webhook{} = webhook), do: Repo.delete(webhook)

  @doc """
  Inserts one Oban delivery job per matching webhook for the given envelope.

  Called by `EdgeAdmin.Events.publish/1` after the broker fan-out. Always
  returns `:ok` — webhook delivery is fire-and-forget from the publish path,
  errors surface inside the worker.

  Walks `list_webhooks/1` page by page so the underlying scan is always
  bounded. Same code path as the public REST filter `?event_type=<type>`;
  the two cannot drift. Per-job `max_attempts` comes from
  `WEBHOOK_MAX_ATTEMPTS` (default 3).
  """
  @spec fan_out(map()) :: :ok
  def fan_out(envelope) do
    max_attempts = Application.get_env(:edge_admin, :webhook_max_attempts, 3)
    count = enqueue_matching_pages(envelope, max_attempts, 1, 0)

    :telemetry.execute(
      [:edge_admin, :webhook, :fan_out],
      %{count: count},
      %{event_type: envelope["type"]}
    )

    :ok
  end

  defp enqueue_matching_pages(envelope, max_attempts, page, count) do
    params = %{
      "event_type" => envelope["type"],
      "page" => to_string(page),
      "page_size" => "1000"
    }

    case list_webhooks(params) do
      {:ok, {webhooks, meta}} ->
        Enum.each(webhooks, fn webhook ->
          %{webhook_id: webhook.id, envelope: envelope}
          |> DeliverEventWorker.new(max_attempts: max_attempts)
          |> Oban.insert!()
        end)

        next_count = count + length(webhooks)

        if meta.has_next_page? do
          enqueue_matching_pages(envelope, max_attempts, page + 1, next_count)
        else
          next_count
        end

      {:error, _meta} ->
        Logger.error("Webhooks.fan_out: failed to page webhooks for event_type=#{envelope["type"]}")
        count
    end
  end

  @doc """
  Delivers one webhook × envelope pair.

  Called by `Workers.DeliverEventWorker`. Returns Oban-shaped tuples so the
  worker can propagate the result directly. Retry budgeting belongs to Oban
  (per-job `max_attempts` is set at fan-out time).

  ## Returns
  - `:ok` - 2xx delivery
  - `{:error, reason}` - Recoverable; Oban schedules a retry until the job's
    `max_attempts` budget is exhausted
  - `{:cancel, reason}` - Terminal; Oban skips remaining retries
  """
  @spec deliver_event(String.t(), map()) :: :ok | {:error, term()} | {:cancel, term()}
  def deliver_event(webhook_id, envelope) do
    case get_webhook(webhook_id) do
      {:error, :not_found} ->
        {:cancel, :webhook_deleted}

      {:ok, webhook} ->
        do_deliver(webhook, envelope)
    end
  end

  defp do_deliver(webhook, envelope) do
    start = System.monotonic_time()
    result = Delivery.send(webhook, envelope)
    duration = System.monotonic_time() - start

    emit_delivery_telemetry(webhook, envelope, result, duration)

    case result do
      :ok -> :ok
      {:recoverable, reason} -> {:error, reason}
      {:terminal, reason} -> {:cancel, {:delivery_failed, reason}}
    end
  end

  defp emit_delivery_telemetry(webhook, envelope, result, duration) do
    outcome =
      case result do
        :ok -> :ok
        {:recoverable, _} -> :recoverable
        {:terminal, _} -> :terminal
      end

    :telemetry.execute(
      [:edge_admin, :webhook, :delivery],
      %{duration: duration},
      %{event_type: envelope["type"], result: outcome, webhook_id: webhook.id}
    )
  end
end
