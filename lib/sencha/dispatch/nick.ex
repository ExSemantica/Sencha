defmodule Sencha.Dispatch.Nick do
  def handle(
        %Sencha.Message{params: [param]},
        pid,
        state = %Sencha.TCP.Client.State{nickname: old}
      ) do
    case Sencha.TCP.Server.nick_lookup(param) do
      {:ok, _} ->
        Sencha.TCP.Client.transmit(
          pid,
          Sencha.Message.form_numeric(:err_nicknameinuse, [param], "Nickname is already in use")
        )

        :ok

      {:error, :not_found} ->
        update_nick(pid, old, param, state)
    end
  end

  def handle(_message, _pid, _state), do: :ok

  defp update_nick(pid, old, new, state = %Sencha.TCP.Client.State{ident: ident, host: host}) do
    case Sencha.TCP.Server.nick_push(new, pid) do
      :ok ->
        Sencha.TCP.Server.nick_pop(old)

        if old != "*" do
          Sencha.TCP.Client.transmit(
            pid,
            Sencha.Message.form_sourced("#{old}!#{ident}@#{host}", "NICK", [new])
          )
        end

        {:ok, %{state | nickname: new}}

      {:error, :invalid} ->
        Sencha.TCP.Client.transmit(
          pid,
          Sencha.Message.form_numeric(:err_erroneousnickname, [new], "Erroneous nickname")
        )

        :ok
    end
  end
end
