defmodule Sencha.Scoreboard do
  @moduledoc """
  Handles counts for 'LUSERS' command

  This requires a Mnesia storage that is globally accessible to all nodes, where
  each server has its own Mnesia table for local storage.

  TODO: finish this
  """
  use GenServer

  @doc """
  Starts the scoreboard process for this node only.
  """
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl GenServer
  def init([]) do
    {:ok, []}
  end
end
