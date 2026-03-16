defmodule Sencha.Commands.Names do
  @moduledoc """
  Handle 'NAMES' IRCv3 commands
  """
  def max_targets(), do: 1

  def handle_irc(
        _pid,
        _packet = %Sencha.Message{params: [params]},
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
        crecipient = GenServer.whereis({:global, {Sencha.Channel, target}})

        {:ok, ustate} = Sencha.User.get_state(user)

        case target do
          "#" <> _channel when is_nil(crecipient) ->
            Sencha.Channel.Names.send_ending(target, ustate)

          "#" <> _channel ->
            {:ok, cstate} = Sencha.Channel.get_state(crecipient)

            if cstate.modes[?s] do
              Sencha.Channel.Names.send_ending(target, ustate)
            else
              Sencha.Channel.Names.send(cstate, ustate)
            end
          _user ->
            # You shouldn't do this, it's invalid.
            :ok
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
