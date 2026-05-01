# edge_admin/lib/edge_admin/sentry/req_client.ex
defmodule EdgeAdmin.Sentry.ReqClient do
  @moduledoc """
  `Sentry.HTTPClient` implementation backed by `Req`.

  Used so the admin doesn't need a second HTTP stack (hackney/finch) just for
  Sentry envelope delivery. Req is already a top-level dependency.
  """

  @behaviour Sentry.HTTPClient

  @impl true
  def post(url, headers, body) do
    case Req.post(url, headers: headers, body: body, decode_body: false) do
      {:ok, %Req.Response{status: status, headers: resp_headers, body: resp_body}} ->
        {:ok, status, flatten_headers(resp_headers), to_binary(resp_body)}

      {:error, error} ->
        {:error, error}
    end
  end

  # Req returns headers as %{name => [values]}; Sentry expects [{name, value}].
  defp flatten_headers(headers) do
    for {name, values} <- headers, value <- values, do: {name, value}
  end

  defp to_binary(body) when is_binary(body), do: body
  defp to_binary(nil), do: ""
  defp to_binary(other), do: IO.iodata_to_binary(List.wrap(other))
end
