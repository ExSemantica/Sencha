defmodule Sencha.Channel do
  @moduledoc """
  IRC channel server
  """
  use GenServer

  # ===========================================================================
  # Public calls
  # ===========================================================================
  def start_link(_init_arg, aggregate: aggregate) do
    where = {:via, Registry, {Sencha.ChannelRegistry, aggregate}}

    GenServer.start_link(__MODULE__, [aggregate: aggregate], name: where)
  end

  @doc """
  Makes the specified username join
  """
  def join(pid, user), do: GenServer.cast(pid, {:join, user})

  @doc """
  Makes the specified username part
  """
  def part(pid, user, reason \\ nil), do: GenServer.cast(pid, {:part, user, reason})

  @doc """
  Makes the specified username talk
  """
  def talk(pid, user, message), do: GenServer.cast(pid, {:talk, user, message})

  @doc """
  Makes the specified username quit
  """
  def quit(pid, user), do: GenServer.cast(pid, {:quit, user})

  @doc """
  Gets all usernames in the channel
  """
  def get_users(pid), do: GenServer.call(pid, :get_users)

  @doc """
  Gets the channel's name
  """
  def get_name(pid), do: GenServer.call(pid, :get_name)

  # ===========================================================================
  # Behavioral callbacks
  # ===========================================================================
  @impl true
  def init(aggregate: aggregate) do
    case aggregate |> lookup_via_gateway do
      {:ok, info} ->
        {:ok,
         %{
           channel: "#" <> (info.aggregate |> String.downcase()),
           topic: info.description,
           usernames: MapSet.new(),
           created: info.inserted_at |> DateTime.to_unix()
         }}

      {:error, what} ->
        {:stop, {:error, what}}
    end
  end

  @impl true
  def handle_cast({:join, user}, state) do
    
  end

  # ===========================================================================
  # Private calls
  # ===========================================================================
  defp lookup_via_gateway(aggregate) do
    # Look for nearest gateway
    fastest_node = Sencha.Gateway.fastest_node()

    # Try to get info from the nearest gateway
    if is_nil(fastest_node) do
      {:error, :no_gateway}
    else
      Sencha.Gateway.aggregate_info(
        fastest_node,
        self(),
        aggregate |> String.replace_prefix("#", "")
      )

      receive do
        {Exsemantica.Gateway, ^fastest_node, {:aggregate_info, {:ok, info}}} ->
          {:ok, info}

        {Exsemantica.Gatewat, ^fastest_node, {:aggregate_info, {:error, what}}} ->
          {:error, what}
      after
        5000 ->
          {:error, :gateway_timeout}
      end
    end
  end
end
