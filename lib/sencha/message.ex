defmodule Sencha.Message do
  @moduledoc """
  RFC 2812-compliant message coding
  """
  @enforce_keys [:command]
  defstruct [:prefix, :command, :params, :trailing]

  @doc """
  Encodes an outgoing IRC command.
  """
  def encode(
        remap = %__MODULE__{prefix: _prefix, command: _command, params: nil, trailing: _trailing}
      ) do
    encode(%__MODULE__{remap | params: []})
  end

  def encode(%__MODULE__{prefix: nil, command: command, params: [], trailing: nil}) do
    "#{command}\r\n"
  end

  def encode(%__MODULE__{prefix: nil, command: command, params: [], trailing: trailing}) do
    "#{command} :#{trailing}\r\n"
  end

  def encode(%__MODULE__{prefix: prefix, command: command, params: [], trailing: nil}) do
    ":#{prefix} #{command}\r\n"
  end

  def encode(%__MODULE__{prefix: prefix, command: command, params: [], trailing: trailing}) do
    ":#{prefix} #{command} :#{trailing}\r\n"
  end

  def encode(%__MODULE__{prefix: nil, command: command, params: params, trailing: nil}) do
    "#{command} #{params |> Enum.join(" ")}\r\n"
  end

  def encode(%__MODULE__{prefix: nil, command: command, params: params, trailing: trailing}) do
    "#{command} #{params |> Enum.join(" ")} :#{trailing}\r\n"
  end

  def encode(%__MODULE__{prefix: prefix, command: command, params: params, trailing: nil}) do
    ":#{prefix} #{command} #{params |> Enum.join(" ")}\r\n"
  end

  def encode(%__MODULE__{prefix: prefix, command: command, params: params, trailing: trailing}) do
    ":#{prefix} #{command} #{params |> Enum.join(" ")} :#{trailing}\r\n"
  end

  @doc """
  Decodes an incoming IRC command.
  """
  def decode(message) do
    message
    |> String.split("\r\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&decode_one/1)
  end

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
end
