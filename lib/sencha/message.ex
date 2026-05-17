defmodule Sencha.Message do
  @moduledoc """
  RFC 2812-compliant IRC message coding
  """
  @enforce_keys [:command]
  defstruct prefix: nil, command: nil, params: nil, trailing: nil

  @numerics %{
    err_erroneousnickname: "432",
    err_nicknameinuse: "433"
  }

  @newline "\r\n"
  @prefix_marker ?:
  @param_separator ?\s

  @doc """
  Encodes an outgoing IRC `Sencha.Message` into an iolist, then converts it
  into a binary.
  """
  def encode(
        remap = %__MODULE__{prefix: _prefix, command: _command, params: nil, trailing: _trailing}
      ) do
    encode(%__MODULE__{remap | params: []})
  end

  def encode(%__MODULE__{prefix: prefix, command: command, params: params, trailing: trailing}) do
    iolist = encode_iolist_trailing(trailing)

    # Since the command is space-separated just include it into the params
    iolist = [encode_iolist_middle([command | params]) | iolist]
    iolist = [encode_iolist_prefix(prefix) | iolist]

    iolist |> :erlang.iolist_to_binary()
  end

  @doc """
  Decodes an incoming IRC command represented as a binary into a
  `Sencha.Message`.
  """
  def decode(message) do
    message
    |> String.split(@newline)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&decode_one/1)
  end

  # ===========================================================================
  defp encode_iolist_prefix(nil), do: []

  defp encode_iolist_prefix(prefix),
    do: [@prefix_marker, prefix, @param_separator]

  defp encode_iolist_middle(command_params),
    do: command_params |> Enum.intersperse(@param_separator)

  defp encode_iolist_trailing(nil), do: [@newline]

  defp encode_iolist_trailing(trailing),
    do: [@param_separator, @prefix_marker, trailing, @newline]

  # ===========================================================================
  defp decode_tail(what) do
    what
    |> String.split(" ", parts: 2)
    |> decode_tail([])
  end

  defp decode_tail([next], ret) do
    if next |> String.starts_with?(":") do
      {ret |> Enum.reverse(), next |> String.replace_prefix(":", "")}
    else
      {[next | ret] |> Enum.reverse(), nil}
    end
  end

  defp decode_tail([next | later], ret) do
    [captured] = later

    if captured |> String.starts_with?(":") do
      {[next | ret] |> Enum.reverse(), captured |> String.replace_prefix(":", "")}
    else
      captured
      |> String.split(" ", parts: 2)
      |> decode_tail([next | ret])
    end
  end

  defp decode_into_structure([tail], prefix) do
    case decode_tail(tail) do
      # Prevent omission of IRC command here
      {ptail, nil} when ptail != [] ->
        [command | parameters] = ptail

        %__MODULE__{
          prefix: prefix,
          command: command,
          params: parameters,
          trailing: nil
        }

      {ptail, trailing} when ptail != [] ->
        [command | parameters] = ptail

        %__MODULE__{
          prefix: prefix,
          command: command,
          params: parameters,
          trailing: trailing
        }
    end
  end

  defp decode_one(message) do
    # One split IRC command
    if message |> String.starts_with?(":") do
      [prefix | tail] = message |> String.replace_prefix(":", "") |> String.split(" ", parts: 2)
      decode_into_structure(tail, prefix)
    else
      decode_into_structure([message], nil)
    end
  end

  def form_error(client, reason) do
    %__MODULE__{command: "ERROR", trailing: "Closing Link: #{client} (#{reason})"}
  end

  def form_sourced(hostmask, command, contents, message \\ nil) do
    %__MODULE__{
      prefix: hostmask,
      command: command,
      params: contents,
      trailing: message
    }
  end

  def form_stringed(command, contents, message \\ nil) do
    %__MODULE__{
      prefix: :persistent_term.get(Sencha.Application.Host),
      command: command,
      params: contents,
      trailing: message
    }
  end

  def form_numeric(numeric, contents, message) do
    %__MODULE__{
      prefix: :persistent_term.get(Sencha.Application.Host),
      command: @numerics[numeric],
      params: contents,
      trailing: message
    }
  end
end
