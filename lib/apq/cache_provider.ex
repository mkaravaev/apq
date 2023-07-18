defmodule Apq.CacheProvider do
  @moduledoc """
  Behaviour that the apq cache needs to conform to.

  """

  @type hash :: String.t()

  @type query_doc :: String.t()

  @type opts :: []

  @doc """
  Get a query document given a hash from the cache
  """
  @callback get(hash, opts) :: {:ok, query_doc} | {:error, nil}

  @doc """
  Put a query document in the cache with the hex-encoded sha256-hash as cache key
  """
  @callback put(hash, query_doc, opts) :: {:ok | :error, boolean}
end
