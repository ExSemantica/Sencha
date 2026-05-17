defmodule Sencha.TCP.Client do
  @moduledoc """
  TCP client for the IRC daemon.
  """
  use GenServer, restart: :temporary
  require Logger

  defmodule __MODULE__.State do
    @moduledoc """
    - `:socket`: the client socket
    - `:fsm_state`: the finite state machine's current state label
    - `:fsm_data`: the finite state machine's extra data
    - `:host`: the host name obtained through `Sencha.ReverseDNS`
    """
    @enforce_keys [:socket, :host]
    defstruct socket: nil,
              fsm_state: :wait_for_connection,
              fsm_data: %{},
              host: nil,
              # FIXME
              ident: "~Sencha",
              # FIXME
              real_name: "Sencha User",
              nickname: "*",
              last_pong: nil
  end

  # ===========================================================================
  # functions
  # ===========================================================================
  @doc """
  Starts the TCP client process.
  """
  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @doc """
  Asynchronously modifies the state of this TCP client.
  """
  def put_state(pid, state) do
    GenServer.cast(pid, {:put_state, state})
  end

  @doc """
  Asynchronously sends a raw message to this TCP client.
  """
  def transmit(pid, message) do
    GenServer.cast(pid, {:transmit, message})
  end

  # ===========================================================================
  # callbacks
  # ===========================================================================
  @impl GenServer
  def init(accept: accept) do
    Logger.debug("Starting TCP client socket")

    __MODULE__.transmit(
      self(),
      Sencha.Message.form_stringed("NOTICE", ["*"], "*** Looking up your hostname...")
    )

    {:ok, {address, _port}} = :inet.peername(accept)
    task = Task.async(fn -> address |> Sencha.ReverseDNS.lookup() end)

    host =
      case Task.await(task, 5000) do
        {:ok, hostname} ->
          __MODULE__.transmit(
            self(),
            Sencha.Message.form_stringed("NOTICE", ["*"], "*** Found your hostname: #{hostname}")
          )

          hostname

        {:error, _} ->
          __MODULE__.transmit(
            self(),
            Sencha.Message.form_stringed("NOTICE", ["*"], "*** Couldn't look up your hostname")
          )

          address |> :inet.ntoa()
      end

    Logger.debug("Socket host is #{host}")
    {:ok, %__MODULE__.State{socket: accept, host: host}}
  end

  @impl GenServer
  def handle_info({:tcp, _socket, data}, state) do
    data
    |> Sencha.Message.decode()
    |> Stream.each(fn message ->
      Logger.debug("RECV: #{inspect(message)}")

      case Sencha.Dispatch.handle_command(message, self(), state) do
        {:ok, new_state} ->
          __MODULE__.put_state(self(), new_state)

        :ok ->
          :ok
      end
    end)
    |> Stream.run()

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:put_state, new_state}, _state) do
    Logger.debug("Socket state changed")
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_cast({:transmit, message}, state = %__MODULE__.State{socket: socket}) do
    Logger.debug("SEND: #{inspect(message)}")

    :gen_tcp.send(
      socket,
      message |> Sencha.Message.encode()
    )

    {:noreply, state}
  end
end
