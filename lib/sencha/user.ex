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
  use GenServer, restart: :temporary

  # ===========================================================================
  # Public API
  # ===========================================================================
  def start_link(socket: socket_pid, ip_address: ip_address, target: target) do
    # At this point we aren't registering the USER/PASS/NICK yet
    GenServer.start_link(__MODULE__, %{ip_address: ip_address, socket: socket_pid, target: target})
  end

  @doc """
  If this user is in the CIDR block, disconnect them

  Don't use a CIDR string here, use an `InetCidr` block
  """
  def check_kline(pid, cidr, reason) do
    GenServer.cast(pid, {:check_kline, cidr, reason})
  end

  # ===========================================================================
  # Callbacks
  # ===========================================================================
  @impl GenServer
  def init(state) do
    {:ok, state}
  end

  @impl GenServer
  def handle_cast(
        {:check_kline, cidr, reason},
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

      Sencha.Socket.disconnect(socket_pid, "*** Banned (#{reason})")
    end

    {:noreply, state}
  end
end
