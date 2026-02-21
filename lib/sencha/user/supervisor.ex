defmodule Sencha.User.Supervisor do
  use DynamicSupervisor

  # ===========================================================================
  # Public callbacks
  # ===========================================================================
  @doc """
  Starts this supervisor.
  """
  def start_link([]) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Starts a `Sencha.User`.
  """
  def start_child(user_args) do
    DynamicSupervisor.start_child(__MODULE__, {Sencha.User, user_args})
  end

  @doc """
  Sends a message to all currently connected clients.
  """
  def wallops(message) do
    workers = DynamicSupervisor.which_children(__MODULE__)

    for {_, pid, _, _} <- workers do
      Sencha.User.wallops(pid, message)
    end
  end

  # ===========================================================================
  # Behavioral callbacks
  # ===========================================================================
  @impl DynamicSupervisor
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
