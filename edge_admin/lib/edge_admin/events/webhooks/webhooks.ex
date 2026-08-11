# edge_admin/lib/edge_admin/events/webhooks/webhooks.ex
defmodule EdgeAdmin.Events.Webhooks do
  @moduledoc """
  Canonical API for configured event webhooks.

  Persistence is delegated to `Resources.Webhooks`; fan-out and delivery are
  delegated to explicit workflows. Webhooks remain immutable after creation.
  """

  alias EdgeAdmin.Events.Webhooks.Resources.Webhooks, as: WebhookResource
  alias EdgeAdmin.Events.Webhooks.Schemas.Webhook
  alias EdgeAdmin.Events.Webhooks.Workflows.Delivery
  alias EdgeAdmin.Events.Webhooks.Workflows.FanOut

  @doc "Lists webhooks with filtering, sorting, and pagination."
  @spec list_webhooks(map()) ::
          {:ok, {[Webhook.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  defdelegate list_webhooks(params \\ %{}), to: WebhookResource, as: :list

  @doc "Gets a webhook by ID."
  @spec get_webhook(String.t()) :: {:ok, Webhook.t()} | {:error, :not_found}
  defdelegate get_webhook(id), to: WebhookResource, as: :get

  @doc "Validates and creates an immutable webhook."
  @spec create_webhook(map()) :: {:ok, Webhook.t()} | {:error, Ecto.Changeset.t()}
  defdelegate create_webhook(attrs \\ %{}), to: WebhookResource, as: :create

  @doc "Deletes a webhook."
  @spec delete_webhook(Webhook.t()) :: {:ok, Webhook.t()} | {:error, Ecto.Changeset.t()}
  defdelegate delete_webhook(webhook), to: WebhookResource, as: :delete

  @doc "Enqueues delivery jobs for every webhook subscribed to the envelope type."
  @spec fan_out(map()) :: :ok
  defdelegate fan_out(envelope), to: FanOut

  @doc "Delivers one webhook envelope and returns an Oban-shaped result."
  @spec deliver_event(String.t(), map()) :: :ok | {:error, term()} | {:cancel, term()}
  defdelegate deliver_event(webhook_id, envelope), to: Delivery
end
