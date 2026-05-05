# edge_admin/lib/edge_admin/events/webhooks/filter.ex
defmodule EdgeAdmin.Events.Webhooks.Filter do
  @moduledoc """
  Wildcard pattern matching for webhook event filters.

  Uses the same wildcard convention as the rest of the admin API
  (`EdgeAdmin.RequestParser`):

    * `*` matches any sequence of characters (including dots, including empty)
    * a literal pattern with no `*` requires exact equality
    * `*` alone matches everything

  ## Examples

      iex> matches?("edge.node.*", "edge.node.registered")
      true

      iex> matches?("edge.node.*", "edge.command_execution.completed")
      false

      iex> matches?("*", "edge.node.registered")
      true

      iex> matches?("edge.node.registered", "edge.node.registered")
      true

  ## Validation

  `validate/1` runs both syntactic and semantic checks. The semantic check
  rejects patterns that match no event type currently in
  `EdgeAdmin.Events.Catalog.all_event_types/0` — catches typos at API time
  rather than at delivery time.
  """

  alias EdgeAdmin.Events.Catalog

  # Pattern characters: lowercase letters, digits, underscores, dots, asterisks.
  # No regex meta-characters are allowed in literals — `*` is the only wildcard.
  @allowed_chars ~r/^[a-z0-9_.\*]+$/

  # ---------------------------------------------------------------------------
  # Matching
  # ---------------------------------------------------------------------------

  @doc """
  Returns true when the pattern matches the event type.

  The pattern is assumed valid — call `validate/1` at create-time to ensure
  this. Behavior on a malformed pattern is unspecified (may match incorrectly
  or fail to match — never raises).
  """
  @spec matches?(String.t(), String.t()) :: boolean()
  def matches?(pattern, event_type) when is_binary(pattern) and is_binary(event_type) do
    if String.contains?(pattern, "*") do
      Regex.match?(compile(pattern), event_type)
    else
      pattern == event_type
    end
  end

  defp compile(pattern) do
    regex_source =
      pattern
      |> String.split("*", trim: false)
      |> Enum.map_join(".*", &Regex.escape/1)

    Regex.compile!("\\A" <> regex_source <> "\\z")
  end

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  @doc """
  Validates a pattern syntactically and against the current event catalog.

  Returns `:ok` or `{:error, reason}` with a human-readable reason.
  """
  @spec validate(String.t()) :: :ok | {:error, String.t()}
  def validate(pattern) when is_binary(pattern) do
    with :ok <- validate_syntax(pattern) do
      validate_matches_catalog(pattern)
    end
  end

  def validate(_), do: {:error, "must be a string"}

  defp validate_syntax(""), do: {:error, "must not be empty"}

  defp validate_syntax(pattern) do
    cond do
      not Regex.match?(@allowed_chars, pattern) ->
        {:error, "must contain only lowercase letters, digits, underscores, dots, and `*`"}

      String.starts_with?(pattern, ".") ->
        {:error, "must not start with a dot"}

      String.ends_with?(pattern, ".") ->
        {:error, "must not end with a dot"}

      String.contains?(pattern, "..") ->
        {:error, "must not contain consecutive dots"}

      true ->
        :ok
    end
  end

  defp validate_matches_catalog(pattern) do
    if Enum.any?(Catalog.all_event_types(), &matches?(pattern, &1)) do
      :ok
    else
      {:error,
       "matches no current event type. Known prefixes: edge.node.*, edge.command_execution.*, edge.self_update_request.*, edge.enrollment_key.*, edge.ssh_username.*"}
    end
  end
end
