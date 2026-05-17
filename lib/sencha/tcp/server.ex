defmodule Sencha.TCP.Server do
  @moduledoc """
  TCP server for the IRC daemon.
  """
  use GenServer
  require Logger

  defmodule __MODULE__.State do
    @moduledoc """
    - `:socket`: the server socket
    - `:logged_in`: all the users who are logged in
    """
    @enforce_keys [:socket, :acceptor]
    defstruct socket: nil, acceptor: nil, logged_in: %{}
  end

  # ===========================================================================
  # functions
  # ===========================================================================
  @doc """
  Starts the TCP server process.
  """
  def start_link(args) do
    GenServer.start_link(__MODULE__, [args], name: __MODULE__)
  end

  @doc """
  Updates a NICK.
  """
  def nick_push(nick, client_pid) do
    GenServer.call(__MODULE__, {:nick_push, nick, client_pid})
  end

  @doc """
  Tries to look up a NICK.
  """
  def nick_lookup(nick) do
    GenServer.call(__MODULE__, {:nick_lookup, nick})
  end

  @doc """
  Pops a NICK.
  """
  def nick_pop(nick) do
    GenServer.cast(__MODULE__, {:nick_pop, nick})
  end

  # ===========================================================================
  # callbacks
  # ===========================================================================
  @impl GenServer
  def init(port: port) do
    Logger.debug("Starting TCP server socket on port #{port}")

    {:ok, socket} =
      :gen_tcp.listen(port, [:binary, packet: :line, active: true, reuseaddr: true])

    {:ok,
     %__MODULE__.State{socket: socket, acceptor: Task.async(fn -> spawn_acceptor(socket) end)}}
  end

  @impl GenServer
  def handle_call(
        {:nick_push, nick, client_pid},
        _from,
        state = %__MODULE__.State{logged_in: logged_in}
      ) do
    nick_downcased = String.downcase(nick, :ascii)

    cond do
      not Sencha.Constrain.valid_nick?(nick) ->
        {:reply, {:error, :invalid}, state}

      true ->
        {:reply, :ok,
         %__MODULE__.State{
           state
           | logged_in: put_in(logged_in, [nick_downcased], {nick, client_pid})
         }}
    end
  end

  @impl GenServer
  def handle_call({:nick_lookup, nick}, _from, state = %__MODULE__.State{logged_in: logged_in}) do
    nick_downcased = String.downcase(nick, :ascii)

    case Map.get(logged_in, nick_downcased) do
      nil ->
        {:reply, {:error, :not_found}, state}

      indexed ->
        {:reply, {:ok, indexed}, state}
    end
  end

  @impl GenServer
  def handle_cast({:nick_pop, nick}, state = %__MODULE__.State{logged_in: logged_in}) do
    nick_downcased = String.downcase(nick, :ascii)

    {:noreply,
     %__MODULE__.State{
       state
       | logged_in: Map.delete(logged_in, nick_downcased)
     }}
  end

  @impl GenServer
  def handle_cast(
        :accept,
        state = %__MODULE__.State{acceptor: acceptor, socket: socket}
      ) do
    Task.yield(acceptor)
    {:noreply, %__MODULE__.State{state | acceptor: Task.async(fn -> spawn_acceptor(socket) end)}}
  end

  defp spawn_acceptor(socket) do
    {:ok, accept} = :gen_tcp.accept(socket)

    case Sencha.TCP.ClientPool.start_child(accept: accept) do
      {:ok, pid} ->
        Logger.debug("Delegating accept to client")
        :gen_tcp.controlling_process(accept, pid)

      {:error, :max_children} ->
        Logger.debug("Couldn't delegate accept due to excess children")

        :gen_tcp.send(
          accept,
          Sencha.Message.form_error("127.0.0.1", "Too many clients on this server")
          |> Sencha.Message.encode()
        )

        :gen_tcp.shutdown(accept, :write)
        :gen_tcp.close(accept)
    end

    GenServer.cast(__MODULE__, :accept)
  end
end
