defmodule Firmowid.Test.Support.AuthEmailHelpers do
  @moduledoc """
  Shared helpers for auth-flow tests that assert on delivered emails.
  """

  import ExUnit.Assertions
  import Swoosh.TestAssertions

  @doc """
  Extracts a token from the most recently asserted email body using the given path prefix.
  """
  @spec extract_token_from_email!(String.t()) :: String.t()
  def extract_token_from_email!(path_prefix) do
    assert_email_sent(fn email ->
      send(self(), {:captured_email, email})
      true
    end)

    assert_receive {:captured_email, email}

    [token] =
      Regex.run(~r{#{Regex.escape(path_prefix)}([^\s]+)}, email.text_body, capture: :all_but_first)

    token
  end

  @doc """
  Removes already delivered Swoosh test emails from the current test process mailbox.
  """
  @spec drain_sent_emails() :: :ok
  def drain_sent_emails do
    receive do
      {:email, _email} -> drain_sent_emails()
    after
      0 -> :ok
    end
  end
end
