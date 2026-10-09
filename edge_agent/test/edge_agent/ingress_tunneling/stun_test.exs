# edge_agent/test/edge_agent/ingress_tunneling/stun_test.exs
defmodule EdgeAgent.IngressTunneling.StunTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias EdgeAgent.IngressTunneling.Stun

  test "decodes an XOR-MAPPED-ADDRESS from a matching Binding response" do
    transaction = :binary.copy(<<7>>, 12)
    magic_cookie = 0x2112A442
    address = {203, 0, 113, 9}
    address_integer = Enum.reduce(Tuple.to_list(address), 0, fn octet, acc -> acc * 256 + octet end)
    port = 34_567
    masked_port = bxor(port, magic_cookie >>> 16)
    masked_address = bxor(address_integer, magic_cookie)

    attribute =
      <<0x0020::unsigned-big-16, 8::unsigned-big-16, 0, 1, masked_port::unsigned-big-16,
        masked_address::unsigned-big-32>>

    response =
      <<0x0101::unsigned-big-16, 12::unsigned-big-16, magic_cookie::unsigned-big-32, transaction::binary,
        attribute::binary>>

    assert {:ok, ^address, ^port} = Stun.mapped_address(response, transaction)
  end

  test "rejects a response for a different transaction" do
    transaction = :binary.copy(<<1>>, 12)
    response = <<0x0101::unsigned-big-16, 0::unsigned-big-16, 0x2112A442::unsigned-big-32, transaction::binary>>

    assert :error = Stun.mapped_address(response, :binary.copy(<<2>>, 12))
  end

  test "rejects a Binding response whose declared length does not match its attributes" do
    transaction = :binary.copy(<<1>>, 12)
    response = <<0x0101::unsigned-big-16, 8::unsigned-big-16, 0x2112A442::unsigned-big-32, transaction::binary>>

    assert :error = Stun.mapped_address(response, transaction)
  end
end
