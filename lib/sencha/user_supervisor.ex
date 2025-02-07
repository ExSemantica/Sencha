defmodule Sencha.UserSupervisor do
  @moduledoc """
  Allows for dynamic, lazy starting of users.
  """
  use DynamicSupervisor

  # Maximum users who can join
  # TODO: Make this a config variable
  @max_users 1024

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Starts a user state.
  """
  def start_child(handle, socket) do
    DynamicSupervisor.start_child(__MODULE__, {Sencha.User, handle: handle, socket: socket})
  end

  @doc """
  Counts how many user states are online at the moment.
  """
  def count_children() do
    DynamicSupervisor.count_children(__MODULE__)
  end

  @doc """
  Deletes a user from the supervisor before `Sencha.Handler` disconnects it.
  """
  def terminate_child(pid) do
    :ok = DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @doc """
  Helper for broadcasting wallops.

  TODO: There should be a function to call for wallops instead!
  """
  def broadcast_wallops(message) do
    children = DynamicSupervisor.which_children(__MODULE__)

    for {_, pid, _, [Sencha.User]} <- children do
      pid |> Sencha.User.wallops(message)
    end

    :ok
  end

  # ===========================================================================
  @impl true
  def init(init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_children: @max_users,
      extra_arguments: [init_arg]
    )
  end
end
