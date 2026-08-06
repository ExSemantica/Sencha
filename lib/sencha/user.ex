# User GenServer/finite state machine
# Copyright 2026 Roland Metivier
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Sencha.User do
  @moduledoc """
  User GenServer/finite state machine

  Unregistered *and* registered users are accounted for, this way
  Originally we needed Mnesia tables to housekeep these counts
  """
  require Logger
  use GenServer, restart: :temporary

  # ===========================================================================
  # Public API
  # ===========================================================================
  def start_link(socket: socket_pid, ip_address: ip_address, target: target) do
    # At this point we aren't registering the USER/PASS/NICK yet
    GenServer.start_link(__MODULE__, %{
      user?: false,
      nick?: false,
      pass?: false,
      ip_address: ip_address,
      socket: socket_pid,
      target: target,
      timeout_auth: nil,
      gecos: nil
    })
  end

  @doc """
  If this user is in the CIDR block, disconnect them

  Don't use a CIDR string here, use an `InetCidr` block
  The ID will be inserted into the ban reason
  """
  def check_kline(pid, cidr, id, reason) do
    GenServer.cast(pid, {:check_kline, cidr, id, reason})
  end

  @doc """
  Handle a `Sencha.Message` asynchronously
  """
  def handle_message(pid, message) do
    GenServer.cast(pid, {:handle_message, message})
  end

  # ===========================================================================
  # Callbacks
  # ===========================================================================
  @impl GenServer
  def init(state) do
    {:ok, %{state | timeout_auth: Process.send_after(self(), :timeout_auth, 15_000)}}
  end

  @impl GenServer
  def handle_info(:timeout_auth, state = %{socket: socket_pid}) do
    Sencha.Socket.disconnect(socket_pid, "Authentication timeout")

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(
        {:handle_message, message = %Sencha.Message{}},
        state = %{timeout_auth: timeout_auth}
      ) do
    Logger.debug(message)
    state = state |> Sencha.Dispatch.handle(message)

    if !!Process.read_timer(timeout_auth) and state.nick? and state.user? do
      Process.cancel_timer(timeout_auth)

      # send the welcome burst
      Sencha.Dispatch.Welcome.send_burst(state)

      # start user ping timers TODO
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(
        {:check_kline, cidr, id, reason},
        state = %{ip_address: ip_address, socket: socket_pid, target: target}
      ) do
    if InetCidr.contains?(cidr, ip_address) do
      Sencha.Socket.message_send(
        socket_pid,
        %Sencha.Message{
          prefix: Application.fetch_env!(:sencha, :hostname),
          command: "465",
          middle: [target[:nickname] || "*"],
          trailing: "You have been banned from this IRC server"
        }
      )

      Sencha.Socket.disconnect(socket_pid, "Banned (##{id}) (#{reason})")
    end

    {:noreply, state}
  end
end
