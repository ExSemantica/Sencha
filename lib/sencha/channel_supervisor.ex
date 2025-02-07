defmodule Sencha.ChannelSupervisor do
  @moduledoc """
  Allows for dynamic, lazy starting of channels.
  """
  use DynamicSupervisor


  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start_child(aggregate) do
    # TODO: When do I finish Sencha's channel system?
    DynamicSupervisor.start_child(
      __MODULE__,
      {Sencha.Channel, aggregate: aggregate |> String.downcase()}
    )
  end

  # ===========================================================================
  @impl true
  def init(init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      extra_arguments: [init_arg]
    )
  end
end
