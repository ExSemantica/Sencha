defmodule Sencha.Numerics do
  @moduledoc """
  Helpers for sending IRC numeric replies
  """
  def send_welcome(socket, nickname: nickname) do
    host = Sencha.ApplicationInfo.get_chat_hostname()

    refreshed =
      Sencha.ApplicationInfo.get_last_refreshed()
      |> Calendar.strftime("%a, %-d %b %Y %X %Z")

    version = Sencha.ApplicationInfo.get_version()

    burst = [
      %Sencha.Message{
        prefix: host,
        command: "001",
        params: [nickname],
        trailing: "Welcome to Sencha, #{nickname}"
      },
      %Sencha.Message{
        prefix: host,
        command: "002",
        params: [nickname],
        trailing: "Your host is #{host}, running version v#{version}"
      },
      %Sencha.Message{
        prefix: host,
        command: "003",
        params: [nickname],
        trailing: "This server was last restarted #{refreshed}"
      },
      %Sencha.Message{
        prefix: host,
        command: "004",
        params: [nickname, "sencha", version]
      },
      %Sencha.Message{
        prefix: host,
        command: "005",
        params: [nickname], # TODO: Proper RPL_ISUPPORT
        trailing: "are supported by this server"
      },
      %Sencha.Message{
        prefix: host,
        command: "422",
        params: [nickname],
        trailing: "MOTD File is unimplemented"
      }
    ]

    for b <- burst do
      socket |> ThousandIsland.Socket.send(b |> Sencha.Message.encode())
    end
  end

  def send(socket, 332, nickname: nickname, channel: channel, topic: topic) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "332",
        params: [nickname, channel],
        trailing: topic
      }
      |> Sencha.Message.encode()
    )
  end

  def send(socket, 333, nickname: nickname, channel: channel, set_by: set_by, set_when: set_when) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "333",
        params: [nickname, channel, set_by, set_when]
      }
      |> Sencha.Message.encode()
    )
  end

  def send(socket, 353, nickname: nickname, channel: channel, users: users) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "353",
        params: [nickname, "=", channel],
        trailing: users |> Enum.join(" ")
      }
      |> Sencha.Message.encode()
    )
  end

  def send(socket, 366, nickname: nickname, channel: channel) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "366",
        params: [nickname, channel],
        trailing: "End of /NAMES list"
      }
      |> Sencha.Message.encode()
    )
  end

  def send(socket, 401, nickname: nickname, recipient: recipient) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "401",
        params: [nickname, recipient],
        trailing: "No such user"
      }
      |> Sencha.Message.encode()
    )
  end

  def send(socket, 403, nickname: nickname, recipient: recipient) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "403",
        params: [nickname, recipient],
        trailing: "No such aggregate"
      }
      |> Sencha.Message.encode()
    )
  end

  def send(socket, 407, nickname: nickname) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "407",
        params: [nickname],
        trailing: "Too many recipients"
      }
      |> Sencha.Message.encode()
    )
  end

  def send(socket, 410, nickname: nickname, capability: capability) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "410",
        params: [nickname || "*", capability],
        trailing: "Invalid CAP command"
      }
      |> Sencha.Message.encode()
    )
  end

  def send(socket, 433, nickname: nickname) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "433",
        params: [nickname],
        trailing: "Account already in use"
      }
      |> Sencha.Message.encode()
    )
  end

  def send(socket, 442, nickname: nickname, recipient: recipient) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "442",
        params: [nickname, recipient],
        trailing: "You're not on that channel"
      }
      |> Sencha.Message.encode()
    )
  end

  def send(socket, 900, nickname: nickname, hostmask: hostmask) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "900",
        params: [nickname, hostmask, nickname],
        trailing: "You are now logged in as #{nickname}"
      }
      |> Sencha.Message.encode()
    )
  end

  def send(socket, 903, nickname: nickname) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "903",
        params: [nickname],
        trailing: "SASL authentication successful"
      }
      |> Sencha.Message.encode()
    )
  end

  def send(socket, 904, []) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "904",
        params: ["*"],
        trailing: "SASL authentication failed"
      }
      |> Sencha.Message.encode()
    )
  end

  def send(socket, 905, nickname: nickname) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "905",
        params: [nickname],
        trailing: "SASL message too long"
      }
      |> Sencha.Message.encode()
    )
  end

  def send(socket, 906, nickname: nickname) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "906",
        params: [nickname],
        trailing: "SASL authentication aborted"
      }
      |> Sencha.Message.encode()
    )
  end

  def send(socket, 907, nickname: nickname) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "907",
        params: [nickname],
        trailing: "You have already authenticated using SASL"
      }
      |> Sencha.Message.encode()
    )
  end

  def send(socket, 908, nickname: nickname) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "908",
        params: [nickname, "PLAIN"],
        trailing: "are available authentication methods"
      }
      |> Sencha.Message.encode()
    )
  end
end
