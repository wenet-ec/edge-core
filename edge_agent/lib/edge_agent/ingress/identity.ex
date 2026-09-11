# edge_agent/lib/edge_agent/ingress/identity.ex
defmodule EdgeAgent.Ingress.Identity do
  @moduledoc """
  Owns the Agent's durable WireGuard identity for future Ingress Tunneling.

  The private key never leaves the Agent. Registration sends only the derived
  public key so Admin can associate it with the existing Node record.
  """

  alias EdgeAgent.Settings

  @curve :x25519

  @doc "Returns the public key for the Agent's durable Ingress identity."
  @spec public_key() :: {:ok, String.t()} | {:error, term()}
  def public_key do
    case Settings.get_ingress_private_key() do
      nil -> generate_and_store_keypair()
      private_key -> public_key_from_private_key(private_key)
    end
  end

  defp generate_and_store_keypair do
    {public_key, private_key} = :crypto.generate_key(:ecdh, @curve)
    encoded_private_key = Base.encode64(private_key)

    case Settings.set_ingress_private_key(encoded_private_key) do
      {:ok, _setting} -> {:ok, Base.encode64(public_key)}
      {:error, reason} -> {:error, {:ingress_private_key_persistence_failed, reason}}
    end
  rescue
    error -> {:error, {:ingress_key_generation_failed, error}}
  end

  defp public_key_from_private_key(encoded_private_key) do
    with {:ok, private_key} <- Base.decode64(encoded_private_key),
         true <- byte_size(private_key) == 32,
         public_key <- :crypto.generate_key(:ecdh, @curve, private_key) do
      {:ok, Base.encode64(public_key)}
    else
      false -> {:error, :invalid_ingress_private_key}
      :error -> {:error, :invalid_ingress_private_key}
    end
  rescue
    error -> {:error, {:ingress_public_key_derivation_failed, error}}
  end
end
