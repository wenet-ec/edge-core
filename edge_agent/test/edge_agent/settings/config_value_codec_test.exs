# edge_agent/test/edge_agent/settings/config_value_codec_test.exs
defmodule EdgeAgent.Settings.ConfigValueCodecTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.Settings.ConfigValueCodec

  test "decodes valid JSON lists and safely handles invalid values" do
    assert ConfigValueCodec.decode_string_list(~s(["a","b"])) == ["a", "b"]
    assert ConfigValueCodec.decode_string_list(nil) == []
    assert ConfigValueCodec.decode_string_list("invalid json") == []
    assert ConfigValueCodec.decode_string_list("{}") == []
  end

  test "encodes string lists for durable settings storage" do
    assert ConfigValueCodec.encode_string_list(["a", "b"]) == ~s(["a","b"])
  end

  test "prepends unique non-empty incoming strings" do
    assert ConfigValueCodec.prepend_new_strings(["", "b", "b", "a"], ["a", "c"]) == ["b", "a", "c"]
  end

  test "encodes and decodes ISO 8601 datetimes" do
    datetime = ~U[2026-08-11 12:00:00Z]
    encoded = ConfigValueCodec.encode_datetime(datetime)

    assert encoded == "2026-08-11T12:00:00Z"
    assert ConfigValueCodec.decode_datetime(encoded) == datetime
    assert ConfigValueCodec.decode_datetime("not-a-datetime") == nil
    assert ConfigValueCodec.decode_datetime(nil) == nil
  end
end
