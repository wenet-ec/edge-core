# edge_agent/lib/edge_agent/ingress_tunneling/derp/frame.ex
defmodule EdgeAgent.IngressTunneling.Derp.Frame do
  @moduledoc "Encodes and decodes DERP's bounded, length-prefixed frames."

  @header_size 5
  @max_frame_size 1_048_576

  @spec encode(byte(), binary()) :: {:ok, binary()} | {:error, :invalid_frame}
  def encode(type, payload) when is_integer(type) and type in 0..255 and is_binary(payload) do
    if byte_size(payload) <= @max_frame_size do
      {:ok, <<type, byte_size(payload)::unsigned-big-32, payload::binary>>}
    else
      {:error, :invalid_frame}
    end
  end

  def encode(_type, _payload), do: {:error, :invalid_frame}

  @spec decode(binary()) :: {:ok, {byte(), binary(), binary()}} | {:error, :incomplete | :invalid_frame}
  def decode(<<type, length::unsigned-big-32, rest::binary>>) when length <= @max_frame_size do
    if byte_size(rest) < length do
      {:error, :incomplete}
    else
      <<payload::binary-size(^length), remaining::binary>> = rest
      {:ok, {type, payload, remaining}}
    end
  end

  def decode(frame) when is_binary(frame) and byte_size(frame) < @header_size, do: {:error, :incomplete}

  def decode(_frame), do: {:error, :invalid_frame}
end
