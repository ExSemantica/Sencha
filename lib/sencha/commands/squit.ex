defmodule Sencha.Commands.Squit do
  @moduledoc """
  Handle 'SQUIT' IRCv3 commands
  """

  def handle_irc(
        _pid,
        _packet = %Sencha.Message{params: [host | reason]},
        {socket,
         _state = %Sencha.Handler.UserState{
           nickname: nickname,
           user_process: user,
           authentication_state: :ok
         }}
      ) do
    ustate = Sencha.User.get_state(user)

    reason = if reason == [] do
      "No reason"
    else
      reason |> Enum.join(" ")
    end

    cond do
      host == Application.fetch_env!(:sencha, :host) and MapSet.member?(ustate.modes, ?o) ->
        # TODO: make it so the host is differentiated from other servers
        Sencha.User.Supervisor.wallops("Server is going offline (#{reason})")

        :init.stop()

      host == Application.fetch_env!(:sencha, :host) ->
        socket
        |> ThousandIsland.Socket.send(
          Sencha.Message.encode(%Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :host),
            command: "481",
            params: [nickname],
            trailing: "Can not stop this server, user is not IRC operator"
          })
        )

      true ->
        :ok
    end

    :ok
  end

  def handle_irc(
        _pid,
        _packet,
        {_socket, _state}
      ) do
    :ok
  end
end
