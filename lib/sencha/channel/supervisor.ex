defmodule Sencha.Channel.Supervisor do
  @moduledoc """
  Supervises `Sencha.Channel` and ensures none of them are duplicates
  """
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
  Starts a `Sencha.Channel`.
  """
  def start_child(channel_args) do
    DynamicSupervisor.start_child(__MODULE__, {Sencha.Channel, channel_args})
  end

  # ===========================================================================
  # Behavioral callbacks
  # ===========================================================================
  @impl DynamicSupervisor
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
