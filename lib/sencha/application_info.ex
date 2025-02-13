defmodule Sencha.ApplicationInfo do
  @moduledoc """
  Handle retrieval of application metadata
  """

  @doc """
  Refresh the application metadata
  """
  def refresh do
    :persistent_term.put(__MODULE__.LastRefreshed, DateTime.utc_now())

    # Get the git commit SHA
    git_commit =
      Application.get_env(:sencha, __MODULE__, %{commit_sha_result: :release})[
        :commit_sha_result
      ]

    # Concatenate it to the Application version, complying with SemVer
    version =
      to_string(Application.spec(:sencha, :vsn)) <>
        if git_commit == :release do
          ""
        else
          {git_commit_sha, 0} = git_commit
          "+git-" <> (git_commit_sha |> String.trim_trailing("\n"))
        end

    # Put it in a persistent_term
    :persistent_term.put(__MODULE__.Version, version)

    # Put the chat hostname in a persistent_term so we can send it as a prefix
    # HexChat is picky about it
    :persistent_term.put(
      __MODULE__.ChatHostname,
      Application.get_env(:sencha, __MODULE__)[:chat_hostname]
    )
  end

  @doc """
  Get the application version as a string

  You must have called `Sencha.ApplicationInfo.refresh` at least once
  before this
  """
  def get_version do
    :persistent_term.get(__MODULE__.Version)
  end

  @doc """
  Gets the last refreshed UTC DateTime.

  Call `Sencha.ApplicationInfo.refresh` once before using this
  function.
  """
  def get_last_refreshed, do: :persistent_term.get(__MODULE__.LastRefreshed)

  @doc """
  Gets the IRC hostname.

  Call `Sencha.ApplicationInfo.refresh` once before using this
  function.
  """
  def get_chat_hostname, do: :persistent_term.get(__MODULE__.ChatHostname)
end
