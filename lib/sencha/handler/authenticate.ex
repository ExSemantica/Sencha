defmodule Sencha.Handler.Authenticate do
  @moduledoc """
  SASL authentication command
  """
  require Logger

  def handle(
        %Sencha.Message{command: "AUTHENTICATE"},
        {socket, state = %Sencha.Handler.UserState{connected?: true, requested_handle: handle}}
      ) do
    nick = handle || "*"

    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "907",
        params: [nick],
        trailing: "You have already authenticated using SASL"
      }
      |> Sencha.Message.encode()
    )

    {:cont, {socket, state}}
  end

  def handle(%Sencha.Message{command: "AUTHENTICATE", params: ["PLAIN"]}, {socket, state}) do
    {:cont, {socket, %Sencha.Handler.UserState{state | sasl_method: :plain}}}
  end

  def handle(
        %Sencha.Message{command: "AUTHENTICATE", params: ["+"]},
        {socket,
         state = %Sencha.Handler.UserState{
           sasl_method: :plain,
           sasl_streaming?: true,
           sasl_data: data
         }}
      )
      when rem(byte_size(data), 400) == 0 do
    data |> try_authenticate({socket, state})
  end

  def handle(
        %Sencha.Message{command: "AUTHENTICATE", params: ["+"]},
        {socket, state = %Sencha.Handler.UserState{sasl_method: :plain}}
      ) do
    {:cont, {socket, %Sencha.Handler.UserState{state | sasl_streaming?: true}}}
  end

  def handle(
        %Sencha.Message{command: "AUTHENTICATE", params: ["*"]},
        {socket, state = %Sencha.Handler.UserState{requested_handle: handle}}
      ) do
    nick = handle || "*"

    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "906",
        params: [nick],
        trailing: "SASL authentication aborted"
      }
      |> Sencha.Message.encode()
    )

    {socket, state} |> Sencha.Handler.quit("SASL authentication aborted")

    {:halt, {socket, state}}
  end

  def handle(
        %Sencha.Message{command: "AUTHENTICATE", params: [new_data]},
        {socket,
         state = %Sencha.Handler.UserState{
           requested_handle: handle,
           sasl_streaming?: true
         }}
      )
      when byte_size(new_data) > 400 do
    nick = handle || "*"

    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "905",
        params: [nick],
        trailing: "SASL message too long"
      }
      |> Sencha.Message.encode()
    )

    {socket, state} |> Sencha.Handler.quit("SASL message too long")

    {:halt, {socket, state}}
  end

  def handle(
        %Sencha.Message{command: "AUTHENTICATE", params: [new_data]},
        {socket,
         state = %Sencha.Handler.UserState{
           sasl_data: existing_data,
           sasl_streaming?: true
         }}
      ) do
    data = existing_data <> new_data

    if rem(byte_size(data), 400) != 0 do
      data |> try_authenticate({socket, state})
    else
      {:cont, {socket, %Sencha.Handler.UserState{state | sasl_data: data}}}
    end
  end

  def handle(
        %Sencha.Message{command: "AUTHENTICATE", params: [_unsupported]},
        {socket, state = %Sencha.Handler.UserState{requested_handle: handle}}
      ) do
    # Client wants an unsupported mechanism. PLAIN is supported but that's all.
    nick = handle || "*"

    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "908",
        params: [nick, "PLAIN"],
        trailing: "are available SASL mechanisms"
      }
      |> Sencha.Message.encode()
    )

    {:cont, {socket, state}}
  end

  # ===========================================================================
  defp try_authenticate(
         sasl_data,
         {socket, state = %Sencha.Handler.UserState{requested_handle: requested_handle}}
       ) do
    split_data = sasl_data |> Base.decode64() |> String.split("\x00")

    user_info =
      cond do
        length(split_data) == 3 ->
          [_authzid, authcid, passwd] = split_data
          lookup_via_gateway(authcid, passwd)

        true ->
          {:error, :bad_sasl}
      end

    case user_info do
      {:ok, %{username: handle}} ->
        {socket, state} |> check_for_others(handle)

      {:error, error} ->
        nick = requested_handle || "*"

        Logger.debug("A user fails to authenticate: #{inspect error}")

        socket
        |> ThousandIsland.Socket.send(
          %Sencha.Message{
            prefix: Sencha.ApplicationInfo.get_chat_hostname(),
            command: "904",
            params: [nick],
            trailing: "SASL authentication failed"
          }
          |> Sencha.Message.encode()
        )

        {socket, state} |> Sencha.Handler.quit("SASL authentication failed")

        {:halt, {socket, state}}
    end
  end

  defp lookup_via_gateway(username, password) do
    # Look for nearest gateway
    fastest_node = Sencha.Gateway.fastest_node()

    # Try to get info from the nearest gateway
    if is_nil(fastest_node) do
      {:error, :no_gateway}
    else
      Sencha.Gateway.user_info(fastest_node, self(), username, password)

      receive do
        {Exsemantica.Gateway, ^fastest_node, {:user_info, {:ok, info}}} ->
          {:ok, info}

        {Exsemantica.Gatewat, ^fastest_node, {:user_info, {:error, what}}} ->
          {:error, what}
      after
        5000 ->
          {:error, :gateway_timeout}
      end
    end
  end

  defp check_for_others({socket, state}, handle) do
    user_status = Sencha.UserSupervisor.start_child(handle, self())

    case user_status do
      {:ok, user_pid} ->
        Logger.debug("#{handle} connects")
        {:cont,
         {socket,
          %Sencha.Handler.UserState{
            state
            | irc_state: :connected,
              connected?: true,
              requested_handle: handle,
              ping_received?: false,
              ping_timer: Process.send_after(self(), :ping, Sencha.Handler.get_ping_interval()),
              timeout_timer: nil,
              user_process: user_pid,
              vhost: "user/#{handle}",
              last_ping: DateTime.utc_now(:second)
          }}
         |> Sencha.Handler.Welcome.send_burst()}

      {:error, {:already_started, _}} ->
        Logger.debug("#{handle} is not unique")

        socket
        |> ThousandIsland.Socket.send(
          %Sencha.Message{
            prefix: Sencha.ApplicationInfo.get_chat_hostname(),
            command: "902",
            params: [handle],
            trailing: "You must use a nick assigned to you"
          }
          |> Sencha.Message.encode()
        )

        {socket, state} |> Sencha.Handler.quit("You must use a nick assigned to you")

        {:halt, {socket, state}}
    end
  end
end
