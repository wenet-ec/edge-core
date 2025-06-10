# edge_admin/lib/edge_admin_web/controllers/nodes/enrollment_key_controller.ex
defmodule EdgeAdminWeb.Nodes.EnrollmentKeyController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdminWeb.Schemas.Nodes.EnrollmentKeySchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback EdgeAdminWeb.FallbackController

  tags ["Nodes"]

  operation :create,
    summary: "Create enrollment key",
    description: "Generate a new enrollment key for edge nodes to join the VPN",
    responses: %{
      201 => {"Enrollment key created", "application/json", EnrollmentKeySchemas.EnrollmentKeyResponse},
      500 => {"VPN service error", "application/json", CommonSchemas.GenericErrorResponse},
      503 => {"VPN service unavailable", "application/json", CommonSchemas.GenericErrorResponse}
    }

  def create(conn, _params) do
    case create_enrollment_key() do
      {:ok, enrollment_data} ->
        conn
        |> put_status(:created)
        |> render(:show, enrollment_key: enrollment_data)

      {:error, :vpn_service_unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "VPN service is currently unavailable"})

      {:error, :edge_nodes_user_not_found} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "edge-nodes user not found in VPN system"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to create enrollment key", details: inspect(reason)})
    end
  end

  # Private functions for the enrollment key creation logic
  defp create_enrollment_key do
    with {:ok, user_id} <- get_edge_nodes_user_id(),
         {:ok, expiration} <- calculate_expiration(),
         {:ok, enrollment_data} <- request_preauth_key(user_id, expiration) do
      {:ok, enrollment_data}
    else
      error -> error
    end
  end

  defp get_edge_nodes_user_id do
    vpn_wrapper_url = Application.get_env(:edge_admin, :vpn_wrapper_url, "http://edge_vpn:8081")

    # Disable retries for better error handling in tests
    req_options = [retry: false]

    case Req.get("#{vpn_wrapper_url}/api/v1/user", [params: [name: "edge-nodes"]] ++ req_options) do
      {:ok, %Req.Response{status: 200, body: response}} when is_map(response) ->
        extract_user_id(response)

      {:ok, %Req.Response{status: _status}} ->
        {:error, :edge_nodes_user_not_found}

      {:error, %Req.TransportError{reason: :econnrefused}} ->
        {:error, :vpn_service_unavailable}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_user_id(%{"users" => users}) when is_list(users) do
    case Enum.find(users, fn user -> user["name"] == "edge-nodes" end) do
      %{"id" => user_id} -> {:ok, user_id}
      nil -> {:error, :edge_nodes_user_not_found}
    end
  end

  defp extract_user_id(%{"id" => user_id}), do: {:ok, user_id}
  defp extract_user_id(_), do: {:error, :edge_nodes_user_not_found}

  defp calculate_expiration do
    expiration =
      DateTime.utc_now()
      |> DateTime.add(1, :hour)
      |> DateTime.to_iso8601()

    {:ok, expiration}
  end

  defp request_preauth_key(user_id, expiration) do
    vpn_wrapper_url = Application.get_env(:edge_admin, :vpn_wrapper_url, "http://edge_vpn:8081")

    request_body = %{
      user: user_id,
      reusable: false,
      ephemeral: false,
      expiration: expiration,
      aclTags: []
    }

    # Disable retries for better error handling in tests
    req_options = [json: request_body, retry: false]

    case Req.post("#{vpn_wrapper_url}/api/v1/preauthkey", req_options) do
      {:ok, %Req.Response{status: 200, body: %{"preAuthKey" => preauth_data}}} ->
        extract_enrollment_data(preauth_data)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:vpn_api_error, status, body}}

      {:error, %Req.TransportError{reason: :econnrefused}} ->
        {:error, :vpn_service_unavailable}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_enrollment_data(preauth_data) do
    enrollment_key = %{
      key: preauth_data["key"],
      expiration: preauth_data["expiration"],
      created_at: preauth_data["createdAt"]
    }

    {:ok, enrollment_key}
  end
end
