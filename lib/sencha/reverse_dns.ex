defmodule Sencha.ReverseDNS do
  @moduledoc """
  Reverse DNS lookup.
  """
  @doc """
  Performs the rDNS lookup.

  Ensure you do this in a `Task` of sorts.
  """
  def lookup(addr) do
    case :inet_res.gethostbyaddr(addr) do
      {:ok, hostent} ->
        {:hostent, h_name, _, _, _, _} = hostent
        {:ok, h_name |> to_string}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
