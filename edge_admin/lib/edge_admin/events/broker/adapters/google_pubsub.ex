# edge_admin/lib/edge_admin/events/broker/adapters/google_pubsub.ex
defmodule EdgeAdmin.Events.Broker.Adapters.GooglePubsub do
  @moduledoc """
  Google Cloud Pub/Sub adapter for the event broker.

  Publishes events to GCP Pub/Sub via the v1 REST API. Pub/Sub is a managed
  service with no on-prem distribution — production always points at real GCP.

  ## Topics

  Five Pub/Sub topics by domain (matches the AWS SNS adapter convention):

      edge-nodes-events
      edge-commands-events
      edge-self-updates-events
      edge-ssh-events
      edge-core-events

  `edge.enrollment_key.*` events also route to `edge-nodes-events` — same
  domain. Topics must be pre-provisioned in the GCP project (Console /
  `gcloud` / Terraform); the adapter does not create them. The full resource
  name is built from `EVENT_BROKER_GOOGLE_PUBSUB_PROJECT` + optional
  `EVENT_BROKER_GOOGLE_PUBSUB_TOPIC_ID_PREFIX` + the suffix above:

      projects/{project}/topics/{prefix}{suffix}

  ## Routing / filtering — message attributes, not topic patterns

  Pub/Sub has no topic-name wildcards. Subscribers filter via *subscription
  filter expressions* evaluated against `attributes` (key/value pairs that
  travel alongside the body). The adapter publishes two attributes:

      type      = "edge.node.status_changed"
      corename  = "prod-us"

  Subscribers can write filter expressions like:

      hasPrefix(attributes.type, "edge.node.")              # all node events
      attributes.type = "edge.command_execution.completed"   # specific event type
      attributes.corename = "prod-us"                        # filter by core instance

  The body remains the full CloudEvents envelope JSON regardless — body and
  attributes carry the same routing fields, so consumers reading the body
  do not need to be aware of attributes.

  ## Wire format

  The Pub/Sub REST API requires the `data` field to be base64-encoded — that's
  the wire-level contract, not an adapter choice. Subscribers receive the
  same bytes; client libraries auto-decode for them.

  ## Durability

  Pub/Sub buffers messages per subscription (default 7-day retention, max 31)
  until the subscriber ACKs them. This is more like SNS+SQS combined than pure
  SNS — durability is built in once a subscription exists. If no subscription
  exists when Edge Core publishes, the message is dropped (same as SNS without
  subscribers).

  ## Auth — standard GCP credential chain (resolved by goth)

  Goth walks the standard GCP credential chain:

  1. `GOOGLE_APPLICATION_CREDENTIALS` env var → service-account JSON file path
     (most common for self-hosted / containerized deployments).
  2. `~/.config/gcloud/application_default_credentials.json` (developer
     workstations after `gcloud auth application-default login`).
  3. GCE / GKE metadata server — Workload Identity on GKE, or the default
     service account on Compute Engine.

  No adapter-specific auth env vars — credentials follow GCP conventions.

  ## Configuration (set in runtime.exs from env vars)

      config :edge_admin, :event_broker_google_pubsub,
        project: "my-project-123",
        topic_id_prefix: "",
        base_url: "https://pubsub.googleapis.com",
        auth: :goth   # :goth | :none

  Controlled by env vars:
  - `EVENT_BROKER_GOOGLE_PUBSUB_PROJECT` — GCP project ID
  - `EVENT_BROKER_GOOGLE_PUBSUB_TOPIC_ID_PREFIX` — optional, e.g. `"edge-prod-"`
    for multiple cores per project
  - `GOOGLE_APPLICATION_CREDENTIALS` — service-account JSON path, used by goth

  `base_url` and `auth` are derived in `runtime.exs` from the deployment
  shape (production targets real GCP with `:goth` auth; staging/CI may
  override the base URL and disable auth via the operator-only
  `EVENT_BROKER_GOOGLE_PUBSUB_EMULATOR_HOST` knob).
  """

  @behaviour EdgeAdmin.Events.Broker.Adapter

  use GenServer

  alias EdgeAdmin.Events.Broker.Adapter

  require Logger

  @goth_name __MODULE__.Goth

  # ---------------------------------------------------------------------------
  # Supervision
  # ---------------------------------------------------------------------------

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :worker,
      restart: :permanent
    }
  end

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Returns the registered Goth process name. The supervisor reads this when
  building children so it can start `{Goth, name: goth_name()}` only when
  `auth: :goth` is configured.
  """
  def goth_name, do: @goth_name

  # ---------------------------------------------------------------------------
  # Adapter callbacks
  # ---------------------------------------------------------------------------

  @impl Adapter
  def healthy? do
    case GenServer.call(__MODULE__, :healthy?) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, "Google Pub/Sub adapter not started"}
  end

  @impl Adapter
  def publish(envelope) do
    GenServer.call(__MODULE__, {:publish, envelope})
  rescue
    _ -> {:error, "Google Pub/Sub adapter not started"}
  end

  # ---------------------------------------------------------------------------
  # GenServer
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init([]) do
    config = Application.get_env(:edge_admin, :event_broker_google_pubsub, [])

    state = %{
      project: Keyword.fetch!(config, :project),
      topic_id_prefix: Keyword.get(config, :topic_id_prefix, ""),
      base_url: Keyword.fetch!(config, :base_url),
      auth: Keyword.fetch!(config, :auth)
    }

    Logger.info(
      "[EventBroker.GooglePubsub] Configured for project=#{state.project} " <>
        "base_url=#{state.base_url} auth=#{state.auth}"
    )

    {:ok, state}
  end

  # Health probe: GET on the node-events topic resource. Validates auth +
  # network + that the topic actually exists (more meaningful than ListTopics).
  @impl GenServer
  def handle_call(:healthy?, _from, state) do
    url = topic_url(state, "edge-nodes-events")

    case Req.get(url, headers: auth_headers(state.auth)) do
      {:ok, %{status: 200}} ->
        {:reply, :ok, state}

      {:ok, %{status: status, body: body}} ->
        {:reply, {:error, "Pub/Sub healthcheck status=#{status}: #{inspect(body)}"}, state}

      {:error, reason} ->
        {:reply, {:error, "Pub/Sub unreachable: #{inspect(reason)}"}, state}
    end
  end

  def handle_call({:publish, envelope}, _from, state) do
    url = topic_url(state, topic_id_for(envelope["type"])) <> ":publish"

    body = %{
      "messages" => [
        %{
          # Pub/Sub REST API requires `data` to be base64-encoded — wire format,
          # not an adapter choice. Subscribers receive the same bytes back.
          "data" => Base.encode64(JSON.encode!(envelope)),
          "attributes" => %{
            "type" => envelope["type"],
            "corename" => envelope["corename"]
          }
        }
      ]
    }

    case Req.post(url, headers: auth_headers(state.auth), json: body) do
      {:ok, %{status: 200}} -> {:reply, :ok, state}
      {:ok, %{status: status, body: response}} -> {:reply, {:error, "status=#{status}: #{inspect(response)}"}, state}
      {:error, reason} -> {:reply, {:error, inspect(reason)}, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp topic_id_for("edge.node." <> _), do: "edge-nodes-events"
  defp topic_id_for("edge.enrollment_key." <> _), do: "edge-nodes-events"
  defp topic_id_for("edge.command_execution." <> _), do: "edge-commands-events"
  defp topic_id_for("edge.self_update_request." <> _), do: "edge-self-updates-events"
  defp topic_id_for("edge.ssh_username." <> _), do: "edge-ssh-events"
  defp topic_id_for("edge.core." <> _), do: "edge-core-events"

  defp topic_url(state, topic_id) do
    "#{state.base_url}/v1/projects/#{state.project}/topics/#{state.topic_id_prefix}#{topic_id}"
  end

  defp auth_headers(:none), do: []

  defp auth_headers(:goth) do
    case Goth.fetch(@goth_name) do
      {:ok, %{token: token}} -> [{"authorization", "Bearer #{token}"}]
      {:error, reason} -> raise "Goth token fetch failed: #{inspect(reason)}"
    end
  end
end
