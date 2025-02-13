defmodule Sencha.Gateway do
  @moduledoc """
  Bridges Sencha with ExSemantica's database
  """
  def fastest_node do
    Node.list() |> Enum.map(&send({Exsemantica.Gateway, &1}, {:ping, self()}))

    receive do
      {ExSemantica.Gateway, fastest, :pong} ->
        fastest
    after
      500 ->
        nil
    end
  end
end
