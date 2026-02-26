defmodule Sencha do
  @moduledoc """
  Documentation for `Sencha`.
  """
  require Logger

  @doc """
  Hello world.

  ## Examples

      iex> Sencha.hello()
      :world

  """
  def hello do
    :world
  end

  def rehash do
    motd_path = Path.join(["data", "motd.txt"])

    case File.read(motd_path) do
      {:ok, motd} ->
        :persistent_term.put(
          Sencha.MOTD,
          motd
          |> String.split("\n")
        )

        Logger.info("Rehashed MOTD at '#{motd_path}'")

      _ ->
        Logger.warning("Could not rehash MOTD at '#{motd_path}'")
    end

    klines_path = Path.join(["data", "klines.txt"])

    case :file.consult(klines_path) do
      {:ok, klines} ->
        :persistent_term.put(
          Sencha.KLines,
          klines
          |> Enum.map(&parse_kline/1)
        )

        Logger.info("Parsed #{length(klines)} K-Lines at '#{klines_path}'")

      _ ->
        Logger.warning("Could not parse K-Lines at '#{klines_path}'")
    end

    :ok
  end

  defp parse_kline({:cidr, cidr_str, reason}) do
    {:cidr, cidr_str |> InetCidr.parse_cidr!(), reason}
  end

  defp parse_kline({:host, host_regex, reason}) do
    {:host, host_regex |> Regex.compile!(), reason}
  end
end
