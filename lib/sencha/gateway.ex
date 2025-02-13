defmodule Sencha.Gateway do
  @moduledoc """
  Bridges Sencha with ExSemantica's database
  """
  def fastest_node do
    Node.list() |> Enum.map(&GenServer.cast({Exsemantica.Gateway, &1}, {:ping, self()}))

    receive do
      {Exsemantica.Gateway, fastest, :pong} ->
        fastest
    after
      500 ->
        nil
    end
  end

  def user_info(target, pid, username, password) do
    GenServer.cast({Exsemantica.Gateway, target}, {:user_info, pid, username, password})
  end

  def aggregate_info(target, pid, aggregate) do
    GenServer.cast({Exsemantica.Gateway, target}, {:aggregate_info, pid, aggregate})
  end
end
