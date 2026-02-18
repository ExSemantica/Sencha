defmodule Sencha.Handler.Capabilities do
  @moduledoc """
  Conveniences for handling IRCv3 capabilities.
  """

  @doc """
  Lists supported IRCv3 capabilities.
  """
  def supported(), do: %{"sasl" => ["PLAIN"]}

  @doc """
  Formats a long form of IRCv3 capabilities.
  ```
  Client: CAP LS 302
  Server: CAP * LS :sasl=PLAIN
  ```
  """
  def format_long({key, nil}) do
    key
  end

  def format_long({key, values}) do
    [key, "=", values |> Enum.intersperse(",")] |> :erlang.iolist_to_binary()
  end
end
