# edge_admin/lib/edge_admin/events/webhooks/resources/webhook_resources.ex
defmodule EdgeAdmin.Events.Webhooks.Resources.WebhookResources do
  @moduledoc """
  Persistence and create-time validation for immutable event webhooks.

  `create/1` persists schema-valid attributes. `create_with_validation/1`
  applies request-form and SSRF validation before inserting the row.
  """

  import Ecto.Query, warn: false
  import EdgeAdmin.Query, only: [case_insensitive_like: 2]

  alias Ecto.Query.CastError
  alias EdgeAdmin.Events.Webhooks.Filters.WebhookFilters
  alias EdgeAdmin.Events.Webhooks.Forms.CreateWebhookForm
  alias EdgeAdmin.Events.Webhooks.Schemas.Webhook
  alias EdgeAdmin.Events.Webhooks.Validators.SsrfValidators
  alias EdgeAdmin.Repo

  @doc "Lists webhooks with filtering, sorting, and pagination."
  @spec list(map()) :: {:ok, {[Webhook.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list(params \\ %{}) do
    {event_type, params} = WebhookFilters.pop_event_type(params)
    flop_params = EdgeAdmin.RequestParser.parse(params)
    {ilike_filters, flop_params} = EdgeAdmin.RequestParser.split_ilike_filters(flop_params, [:url])

    query =
      ilike_filters
      |> Enum.reduce(Webhook, fn %{field: field, value: value}, acc ->
        from(w in acc, where: case_insensitive_like(field(w, ^field), ^value))
      end)
      |> WebhookFilters.filter_by_event_type(event_type)

    Flop.validate_and_run(query, flop_params, for: Webhook, replace_invalid_params: true)
  end

  @spec get(String.t()) :: {:ok, Webhook.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(Webhook, id) do
      nil -> {:error, :not_found}
      webhook -> {:ok, webhook}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @spec create(map()) :: {:ok, Webhook.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs), do: %Webhook{} |> Webhook.changeset(attrs) |> Repo.insert()

  @spec delete(Webhook.t()) :: {:ok, Webhook.t()} | {:error, Ecto.Changeset.t()}
  def delete(%Webhook{} = webhook), do: Repo.delete(webhook)

  @doc "Validates request attributes and the target URL before creating an immutable webhook."
  @spec create_with_validation(map()) :: {:ok, Webhook.t()} | {:error, Ecto.Changeset.t()}
  def create_with_validation(attrs \\ %{}) do
    with {:ok, validated_attrs} <- CreateWebhookForm.changeset(attrs),
         {:ok, validated_attrs} <- validate_ssrf(validated_attrs) do
      create(validated_attrs)
    end
  end

  defp validate_ssrf(%{"url" => url} = attrs) do
    case SsrfValidators.validate_url(url) do
      :ok ->
        {:ok, attrs}

      {:error, reason} ->
        changeset = Webhook.changeset(%Webhook{}, attrs)
        {:error, Ecto.Changeset.add_error(changeset, :url, SsrfValidators.format_error(reason))}
    end
  end

  defp validate_ssrf(attrs), do: {:ok, attrs}
end
