defmodule Sencha.Commands.Notice do
  @moduledoc """
  Handle 'NOTICE' IRCv3 commands
  """
  def max_targets(), do: 1

  def handle_irc(
        pid,
        _packet = %Sencha.Message{params: [params], trailing: message},
        {_socket,
         _state = %Sencha.Handler.UserState{
           nickname: nickname,
           user_process: user,
           authentication_state: :ok
         }}
      ) do
    targets = params |> String.split(",")

    if length(targets) > max_targets() do
      Sencha.Handler.send_message(user, %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "407",
        params: [nickname],
        trailing: "You have specified too many targets"
      })
    else
      for target <- targets do
        urecipient = GenServer.whereis({:global, {Sencha.User, target}})
        crecipient = GenServer.whereis({:global, {Sencha.Channel, target}})

        case target do
          "#" <> _channel when is_nil(crecipient) ->
            Sencha.Handler.send_message(pid, %Sencha.Message{
              prefix: Application.fetch_env!(:sencha, :host),
              command: "403",
              params: [nickname, target],
              trailing: "No such channel"
            })

          "#" <> _channel ->
            {:ok, ustate} = Sencha.User.get_state(user)

            Sencha.Channel.send_message(crecipient, user, %Sencha.Message{
              prefix: Sencha.User.State.hostmask(ustate),
              command: "NOTICE",
              params: [target],
              trailing: message
            })

          _user when is_nil(urecipient) ->
            Sencha.Handler.send_message(pid, %Sencha.Message{
              prefix: Application.fetch_env!(:sencha, :host),
              command: "401",
              params: [nickname, target],
              trailing: "No such user"
            })

          _user ->
            {:ok, ustate} = Sencha.User.get_state(user)
            Sencha.User.notice(urecipient, Sencha.User.State.hostmask(ustate), message)
        end
      end
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
