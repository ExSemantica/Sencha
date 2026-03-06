defmodule Sencha.Commands.Oper do
  @moduledoc """
  Handle 'OPER' IRCv3 commands
  """

  def handle_irc(
        _pid,
        _packet = %Sencha.Message{params: [totp, password], trailing: nil},
        {socket,
         %Sencha.Handler.UserState{
           nickname: nickname,
           user_process: user,
           authentication_state: :ok
         }}
      ) do
    {:ok, ustate} = Sencha.User.get_state(user)

    case Sencha.User.Operator.check_authorized(ustate, password, totp) do
      :ok ->
        Sencha.User.grant_operator(user)

      {:error, :not_operator} ->
        socket
        |> ThousandIsland.Socket.send(
          Sencha.Message.encode(%Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :host),
            command: "491",
            params: [nickname],
            trailing: "No O-lines for your host"
          })
        )

      {:error, :invalid_password} ->
        socket
        |> ThousandIsland.Socket.send(
          Sencha.Message.encode(%Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :host),
            command: "464",
            params: [nickname],
            trailing: "Credentials incorrect"
          })
        )
    end

    :ok
  end

  def handle_irc(
        _pid,
        _packet,
        {socket,
         _state = %Sencha.Handler.UserState{nickname: nickname, authentication_state: :ok}}
      ) do
    socket
    |> ThousandIsland.Socket.send(
      Sencha.Message.encode(%Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "461",
        params: [nickname, "OPER"],
        trailing: "Bad parameters"
      })
    )

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
