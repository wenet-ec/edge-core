# edge_admin/lib/edge_admin/events/webhooks/resources/webhooks.ex
defmodule EdgeAdmin.Events.Webhooks.Resources.Webhooks do
  @moduledoc "Persistence and filtering for configured event webhooks."

  import Ecto.Query, warn: false
  import EdgeAdmin.Query, only: [case_insensitive_like: 2]

  alias Ecto.Query.CastError
  alias EdgeAdmin.Events.Webhooks.Filters.WebhookFilters
  alias EdgeAdmin.Events.Webhooks.Forms
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

  @doc "Gets a webhook by ID."
  @spec get(String.t()) :: {:ok, Webhook.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(Webhook, id) do
      nil -> {:error, :not_found}
      webhook -> {:ok, webhook}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @doc "Validates and creates an immutable webhook."
  @spec create(map()) :: {:ok, Webhook.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs \\ %{}) do
    with {:ok, validated_attrs} <- Forms.CreateWebhookForm.changeset(attrs),
         {:ok, validated_attrs} <- validate_ssrf(validated_attrs) do
      %Webhook{}
      |> Webhook.changeset(validated_attrs)
      |> Repo.insert()
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

  @doc "Deletes a webhook."
  @spec delete(Webhook.t()) :: {:ok, Webhook.t()} | {:error, Ecto.Changeset.t()}
  def delete(%Webhook{} = webhook), do: Repo.delete(webhook)
end
