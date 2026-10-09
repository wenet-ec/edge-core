# edge_agent/test/edge_agent/ingress_tunneling/derp/frame_test.exs
defmodule EdgeAgent.IngressTunneling.Derp.FrameTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.IngressTunneling.Derp.Frame

  test "encodes and decodes a DERP frame while preserving following bytes" do
    assert {:ok, frame} = Frame.encode(4, <<1, 2, 3>>)
    assert frame == <<4, 0, 0, 0, 3, 1, 2, 3>>
    assert {:ok, {4, <<1, 2, 3>>, <<9>>}} = Frame.decode(frame <> <<9>>)
  end

  test "reports incomplete headers and bodies" do
    assert {:error, :incomplete} = Frame.decode(<<4, 0, 0>>)
    assert {:error, :incomplete} = Frame.decode(<<4, 0, 0, 0, 2, 1>>)
  end

  test "rejects frames larger than the protocol limit" do
    assert {:error, :invalid_frame} = Frame.decode(<<4, 0, 16, 0, 1>>)
    assert {:error, :invalid_frame} = Frame.encode(4, :not_a_binary)
  end
end
