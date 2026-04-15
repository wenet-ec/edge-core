# edge_admin/test/edge_admin_web/response_envelope_test.exs
defmodule EdgeAdminWeb.ResponseEnvelopeTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias EdgeAdminWeb.ResponseEnvelope

  defp fake_conn(request_id \\ "test-uuid-1234") do
    :get
    |> conn("/")
    |> Plug.Conn.assign(:request_id, request_id)
  end

  defp fake_flop_meta(overrides \\ []) do
    struct(
      Flop.Meta,
      Keyword.merge(
        [
          current_page: 1,
          page_size: 20,
          total_count: 10,
          total_pages: 1,
          has_next_page?: false,
          has_previous_page?: false,
          next_page: nil,
          previous_page: nil
        ],
        overrides
      )
    )
  end

  # -----------------------------------------------------------------------
  # success/2 — single resource
  # -----------------------------------------------------------------------

  describe "success/2 — single resource" do
    test "returns a map with :data key" do
      result = ResponseEnvelope.success(fake_conn(), %{id: "abc"})
      assert Map.has_key?(result, :data)
    end

    test "returns a map with :meta key" do
      result = ResponseEnvelope.success(fake_conn(), %{id: "abc"})
      assert Map.has_key?(result, :meta)
    end

    test "data is passed through unchanged" do
      payload = %{id: "abc", name: "test"}
      result = ResponseEnvelope.success(fake_conn(), payload)
      assert result.data == payload
    end

    test "meta contains request_id from conn.assigns" do
      result = ResponseEnvelope.success(fake_conn("my-request-id"), %{})
      assert result.meta.request_id == "my-request-id"
    end

    test "meta contains timestamp" do
      result = ResponseEnvelope.success(fake_conn(), %{})
      assert Map.has_key?(result.meta, :timestamp)
      assert is_binary(result.meta.timestamp)
    end

    test "timestamp is ISO 8601 formatted" do
      result = ResponseEnvelope.success(fake_conn(), %{})
      assert result.meta.timestamp =~ ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/
    end

    test "meta does NOT contain pagination key" do
      result = ResponseEnvelope.success(fake_conn(), %{})
      refute Map.has_key?(result.meta, :pagination)
    end

    test "meta has exactly request_id and timestamp" do
      result = ResponseEnvelope.success(fake_conn(), %{})

      assert MapSet.equal?(
               MapSet.new(Map.keys(result.meta)),
               MapSet.new([:request_id, :timestamp])
             )
    end

    test "data can be a list" do
      result = ResponseEnvelope.success(fake_conn(), [1, 2, 3])
      assert result.data == [1, 2, 3]
    end

    test "data can be nil" do
      result = ResponseEnvelope.success(fake_conn(), nil)
      assert result.data == nil
    end
  end

  # -----------------------------------------------------------------------
  # success/3 — paginated collection
  # -----------------------------------------------------------------------

  describe "success/3 — paginated collection" do
    test "returns a map with :data key" do
      result = ResponseEnvelope.success(fake_conn(), [], fake_flop_meta())
      assert Map.has_key?(result, :data)
    end

    test "returns a map with :meta key" do
      result = ResponseEnvelope.success(fake_conn(), [], fake_flop_meta())
      assert Map.has_key?(result, :meta)
    end

    test "data is passed through unchanged" do
      result = ResponseEnvelope.success(fake_conn(), [%{id: "1"}, %{id: "2"}], fake_flop_meta())
      assert result.data == [%{id: "1"}, %{id: "2"}]
    end

    test "meta contains request_id from conn.assigns" do
      result = ResponseEnvelope.success(fake_conn("pag-req-id"), [], fake_flop_meta())
      assert result.meta.request_id == "pag-req-id"
    end

    test "meta contains pagination key" do
      result = ResponseEnvelope.success(fake_conn(), [], fake_flop_meta())
      assert Map.has_key?(result.meta, :pagination)
    end

    test "meta has exactly request_id, timestamp, pagination" do
      result = ResponseEnvelope.success(fake_conn(), [], fake_flop_meta())

      assert MapSet.equal?(
               MapSet.new(Map.keys(result.meta)),
               MapSet.new([:request_id, :timestamp, :pagination])
             )
    end
  end

  # -----------------------------------------------------------------------
  # success/3 — pagination field renames
  # -----------------------------------------------------------------------

  describe "success/3 — pagination field mapping from Flop.Meta" do
    test "current_page renamed to page" do
      result = ResponseEnvelope.success(fake_conn(), [], fake_flop_meta(current_page: 3))
      assert result.meta.pagination.page == 3
      refute Map.has_key?(result.meta.pagination, :current_page)
    end

    test "total_count renamed to total" do
      result = ResponseEnvelope.success(fake_conn(), [], fake_flop_meta(total_count: 99))
      assert result.meta.pagination.total == 99
      refute Map.has_key?(result.meta.pagination, :total_count)
    end

    test "has_next_page? renamed to has_next" do
      result = ResponseEnvelope.success(fake_conn(), [], fake_flop_meta(has_next_page?: true))
      assert result.meta.pagination.has_next == true
      refute Map.has_key?(result.meta.pagination, :has_next_page?)
    end

    test "has_previous_page? renamed to has_prev" do
      result = ResponseEnvelope.success(fake_conn(), [], fake_flop_meta(has_previous_page?: true))
      assert result.meta.pagination.has_prev == true
      refute Map.has_key?(result.meta.pagination, :has_previous_page?)
    end

    test "page_size passed through unchanged" do
      result = ResponseEnvelope.success(fake_conn(), [], fake_flop_meta(page_size: 50))
      assert result.meta.pagination.page_size == 50
    end

    test "total_pages passed through unchanged" do
      result = ResponseEnvelope.success(fake_conn(), [], fake_flop_meta(total_pages: 7))
      assert result.meta.pagination.total_pages == 7
    end

    test "next_page is nil when no next page" do
      result = ResponseEnvelope.success(fake_conn(), [], fake_flop_meta(has_next_page?: false, next_page: nil))
      assert result.meta.pagination.next_page == nil
    end

    test "next_page is set when there is a next page" do
      result = ResponseEnvelope.success(fake_conn(), [], fake_flop_meta(has_next_page?: true, next_page: 2))
      assert result.meta.pagination.next_page == 2
    end

    test "prev_page is nil when no previous page" do
      result = ResponseEnvelope.success(fake_conn(), [], fake_flop_meta(has_previous_page?: false, previous_page: nil))
      assert result.meta.pagination.prev_page == nil
    end

    test "prev_page is set when there is a previous page" do
      result = ResponseEnvelope.success(fake_conn(), [], fake_flop_meta(has_previous_page?: true, previous_page: 1))
      assert result.meta.pagination.prev_page == 1
    end

    test "pagination has exactly the expected keys" do
      result = ResponseEnvelope.success(fake_conn(), [], fake_flop_meta())

      assert MapSet.equal?(
               MapSet.new(Map.keys(result.meta.pagination)),
               MapSet.new([:page, :page_size, :total, :total_pages, :has_next, :has_prev, :next_page, :prev_page])
             )
    end
  end

  # -----------------------------------------------------------------------
  # error/3 — simple error (details: nil)
  # -----------------------------------------------------------------------

  describe "error/3 — simple error" do
    test "returns a map with :error key" do
      result = ResponseEnvelope.error(fake_conn(), "not_found", "Resource not found")
      assert Map.has_key?(result, :error)
    end

    test "returns a map with :meta key" do
      result = ResponseEnvelope.error(fake_conn(), "not_found", "Resource not found")
      assert Map.has_key?(result, :meta)
    end

    test "error.code is set correctly" do
      result = ResponseEnvelope.error(fake_conn(), "not_found", "Resource not found")
      assert result.error.code == "not_found"
    end

    test "error.message is set correctly" do
      result = ResponseEnvelope.error(fake_conn(), "not_found", "Resource not found")
      assert result.error.message == "Resource not found"
    end

    test "error.details is nil" do
      result = ResponseEnvelope.error(fake_conn(), "not_found", "Resource not found")
      assert result.error.details == nil
    end

    test "meta contains request_id" do
      result = ResponseEnvelope.error(fake_conn("err-req-id"), "not_found", "Resource not found")
      assert result.meta.request_id == "err-req-id"
    end

    test "error has exactly code, message, details" do
      result = ResponseEnvelope.error(fake_conn(), "not_found", "Resource not found")

      assert MapSet.equal?(
               MapSet.new(Map.keys(result.error)),
               MapSet.new([:code, :message, :details])
             )
    end
  end

  # -----------------------------------------------------------------------
  # error/4 — error with details
  # -----------------------------------------------------------------------

  describe "error/4 — error with details" do
    test "error.details is set to the provided map" do
      details = %{name: ["can't be blank"]}
      result = ResponseEnvelope.error(fake_conn(), "validation_failed", "Validation failed", details)
      assert result.error.details == details
    end

    test "error.code is set correctly" do
      result = ResponseEnvelope.error(fake_conn(), "validation_failed", "Validation failed", %{})
      assert result.error.code == "validation_failed"
    end

    test "nil details is passed through" do
      result = ResponseEnvelope.error(fake_conn(), "conflict", "Conflict", nil)
      assert result.error.details == nil
    end

    test "meta still contains request_id when details provided" do
      result = ResponseEnvelope.error(fake_conn("det-req-id"), "validation_failed", "Validation failed", %{name: []})
      assert result.meta.request_id == "det-req-id"
    end
  end
end
