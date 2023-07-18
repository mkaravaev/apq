defmodule Apq.DocumentProviderTest do
  use Apq.Plug.TestCase
  alias Apq.TestSchema

  import Mox

  setup :verify_on_exit!

  defmodule ApqDocumentWithCacheMock do
    use Apq.DocumentProvider, cache_provider: Apq.CacheMock
  end

  defmodule ApqDocumentWithJsonCodec do
    use Apq.DocumentProvider, cache_provider: Apq.CacheMock, json_codec: Jason
  end

  defmodule ApqDocumentMaxFileSizeMock do
    use Apq.DocumentProvider, cache_provider: Apq.CacheMock, max_query_size: 0
  end

  @query """
  query FooQuery($id: ID!) {
    item(id: $id) {
      name
    }
  }
  """

  @result ~s({"data":{"item":{"name":"Foo"}}})

  @opts Absinthe.Plug.init(
          schema: TestSchema,
          document_providers: [__MODULE__.ApqDocumentWithCacheMock],
          json_codec: Jason
        )

  test "sends persisted query hash in extensions without query and no cache hit" do
    digest = sha256_hexdigest(@query)

    Apq.CacheMock
    |> expect(:get, fn incoming_digest, _opts ->
      assert incoming_digest == digest
      {:ok, nil}
    end)

    assert %{status: status, resp_body: _resp_body} =
             conn(:post, "/", %{
               "extensions" => %{
                 "persistedQuery" => %{"version" => 1, "sha256Hash" => digest}
               },
               "variables" => %{"id" => "foo"}
             })
             |> put_req_header("content-type", "application/graphql")
             |> plug_parser
             |> Absinthe.Plug.call(@opts)

    assert status == 200
  end

  test "sends persisted query hash in extensions without query and cache hit" do
    digest = sha256_hexdigest(@query)

    Apq.CacheMock
    |> expect(:get, fn incoming_digest, _opts ->
      assert incoming_digest == digest
      {:ok, @query}
    end)

    assert %{status: status, resp_body: resp_body} =
             conn(:post, "/", %{
               "extensions" => %{
                 "persistedQuery" => %{"version" => 1, "sha256Hash" => digest}
               },
               "variables" => %{"id" => "foo"}
             })
             |> put_req_header("content-type", "application/graphql")
             |> plug_parser
             |> Absinthe.Plug.call(@opts)

    assert resp_body == @result

    assert status == 200
  end

  test "sends persisted query hash in extensions with query" do
    digest = sha256_hexdigest(@query)
    query = @query

    Apq.CacheMock
    |> expect(:put, fn incoming_digest, incoming_query, _opts ->
      assert incoming_query == query
      assert incoming_digest == digest

      {:ok, query}
    end)

    assert %{status: 200, resp_body: resp_body} =
             conn(:post, "/", %{
               "query" => @query,
               "extensions" => %{
                 "persistedQuery" => %{"version" => 1, "sha256Hash" => digest}
               },
               "variables" => %{"id" => "foo"}
             })
             |> put_req_header("content-type", "application/graphql")
             |> plug_parser
             |> Absinthe.Plug.call(@opts)

    assert resp_body == @result
  end

  test "decodes 'extensions' params if sent as JSON" do
    opts =
      Absinthe.Plug.init(
        schema: TestSchema,
        document_providers: [
          __MODULE__.ApqDocumentWithJsonCodec
        ]
      )

    digest = sha256_hexdigest(@query)
    query = @query
    extensions = Jason.encode!(%{"persistedQuery" => %{"version" => 1, "sha256Hash" => digest}})

    Apq.CacheMock
    |> expect(:put, fn incoming_digest, incoming_query, _opts ->
      assert incoming_query == query
      assert incoming_digest == digest

      {:ok, query}
    end)

    assert %{status: 200, resp_body: resp_body} =
             conn(:get, "/", %{
               "query" => @query,
               "extensions" => extensions,
               "variables" => %{"id" => "foo"}
             })
             |> put_req_header("content-type", "application/graphql")
             |> plug_parser
             |> Absinthe.Plug.call(opts)

    assert resp_body == @result
  end

  test "raises a sensible error if params are JSON with no json_codec" do
    opts =
      Absinthe.Plug.init(
        schema: TestSchema,
        document_providers: [
          __MODULE__.ApqDocumentWithCacheMock
        ]
      )

    digest = sha256_hexdigest(@query)
    extensions = Jason.encode!(%{"persistedQuery" => %{"version" => 1, "sha256Hash" => digest}})

    assert_raise RuntimeError, "json_codec must be specified and respond to decode!/1", fn ->
      conn(:get, "/", %{
        "query" => @query,
        "extensions" => extensions
      })
      |> put_req_header("content-type", "application/graphql")
      |> plug_parser
      |> Absinthe.Plug.call(opts)
    end
  end

  test "returns error when provided hash does not match calculated query hash" do
    digest = "bogus digest"

    assert %{status: status, resp_body: resp_body} =
             conn(:post, "/", %{
               "query" => @query,
               "extensions" => %{
                 "persistedQuery" => %{"version" => 1, "sha256Hash" => digest}
               },
               "variables" => %{"id" => "foo"}
             })
             |> put_req_header("content-type", "application/graphql")
             |> plug_parser
             |> Absinthe.Plug.call(@opts)

    assert resp_body == ~s({\"errors\":[{\"message\":\"ProvidedShaDoesNotMatch\"}]})

    assert status == 200
  end

  test "does not halt on query without extensions" do
    assert_raise FunctionClauseError, fn ->
      conn(:post, "/", %{
        "query" => @query,
        "variables" => %{"id" => "foo"}
      })
      |> put_req_header("content-type", "application/graphql")
      |> plug_parser
      |> Absinthe.Plug.call(@opts)
    end
  end

  test "it passes through queries without extension to default provider" do
    opts =
      Absinthe.Plug.init(
        schema: TestSchema,
        document_providers: [
          __MODULE__.ApqDocumentWithCacheMock,
          Absinthe.Plug.DocumentProvider.Default
        ],
        json_codec: Jason
      )

    assert %{status: 200, resp_body: resp_body} =
             conn(:post, "/", %{
               "query" => @query,
               "variables" => %{"id" => "foo"}
             })
             |> put_req_header("content-type", "application/graphql")
             |> plug_parser
             |> Absinthe.Plug.call(opts)

    assert resp_body == @result
  end

  test "returns error with invalid query" do
    digest = "bogus digest"

    assert %{status: status, resp_body: resp_body} =
             conn(:post, "/", %{
               "query" => %{"a" => 1},
               "extensions" => %{
                 "persistedQuery" => %{"version" => 1, "sha256Hash" => digest}
               },
               "variables" => %{"id" => "foo"}
             })
             |> put_req_header("content-type", "application/graphql")
             |> plug_parser
             |> Absinthe.Plug.call(@opts)

    assert resp_body == ~s({\"errors\":[{\"message\":\"QueryFormatIncorrect\"}]})

    assert status == 200
  end

  test "returns error with invalid hash and valid query" do
    assert %{status: status, resp_body: resp_body} =
             conn(:post, "/", %{
               "query" => @query,
               "extensions" => %{
                 "persistedQuery" => %{"version" => 1, "sha256Hash" => %{"a" => 1}}
               },
               "variables" => %{"id" => "foo"}
             })
             |> put_req_header("content-type", "application/graphql")
             |> plug_parser
             |> Absinthe.Plug.call(@opts)

    assert resp_body == ~s({\"errors\":[{\"message\":\"HashFormatIncorrect\"}]})

    assert status == 200
  end

  test "returns error with invalid hash and no query" do
    assert %{status: status, resp_body: resp_body} =
             conn(:post, "/", %{
               "extensions" => %{
                 "persistedQuery" => %{"version" => 1, "sha256Hash" => %{"a" => 1}}
               },
               "variables" => %{"id" => "foo"}
             })
             |> put_req_header("content-type", "application/graphql")
             |> plug_parser
             |> Absinthe.Plug.call(@opts)

    assert resp_body == ~s({\"errors\":[{\"message\":\"HashFormatIncorrect\"}]})

    assert status == 200
  end

  test "returns error when query size above max_query_size" do
    digest = sha256_hexdigest(@query)

    opts =
      Absinthe.Plug.init(
        schema: TestSchema,
        document_providers: [
          __MODULE__.ApqDocumentMaxFileSizeMock
        ],
        json_codec: Jason
      )

    assert %{status: status, resp_body: resp_body} =
             conn(:post, "/", %{
               "query" => @query,
               "extensions" => %{
                 "persistedQuery" => %{"version" => 1, "sha256Hash" => digest}
               },
               "variables" => %{"id" => "foo"}
             })
             |> put_req_header("content-type", "application/graphql")
             |> plug_parser
             |> Absinthe.Plug.call(opts)

    assert resp_body == ~s({\"errors\":[{\"message\":\"PersistedQueryLargerThanMaxSize\"}]})

    assert status == 200
  end
end
