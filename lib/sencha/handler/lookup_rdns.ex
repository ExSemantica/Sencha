defmodule Sencha.Handler.LookupRDNS do
  @moduledoc """
  Reverse DNS lookup task
  """

  @doc """
  Performs the rDNS lookup

  Ensure you do this in a `Task` of sorts
  """
  def lookup(addr) do
    case :inet_res.gethostbyaddr(addr) do
      {:ok, hostent} ->
        {:hostent, h_name, _, _, _, _} = hostent
        h_name |> to_string

      {:error, _reason} ->
        :error
    end
  end
end
