defmodule Firmowid.Ash.Invoicing.SalesInvoice.EmailRecipientEligibility do
  @moduledoc """
  Checks if counterparty connected to SalesInvoice has valid email for invoice email delivery.
  """

  alias Firmowid.Ash.Invoicing.Counterparty
  alias Firmowid.Ash.Scope

  @no_counterparty "Faktura nie ma przypisanego kontrahenta."
  @no_counterparty_email "Kontrahent przypisany do faktury nie posiada wprowadzonego adresu email."
  @invalid_counterparty_email "Kontrahent przypisany do faktury posiada niepoprawny adres email."
  @email_regex ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  @type result :: {:ok, String.t()} | {:error, String.t(), String.t() | nil}

  @doc """
  Fetches a valid, trimmed email recipient for a counterparty ID.
  """
  @spec fetch_valid_counterparty_email(String.t() | nil, Scope.t()) :: result()
  def fetch_valid_counterparty_email(nil, _scope), do: {:error, @no_counterparty, nil}

  def fetch_valid_counterparty_email(counterparty_id, scope) do
    case Counterparty.get(counterparty_id, scope: scope) do
      {:ok, %{email: email}} -> validate_email(email)
      {:ok, nil} -> {:error, @no_counterparty, nil}
      {:ok, _counterparty} -> {:error, @no_counterparty_email, nil}
      {:error, _error} -> {:error, @no_counterparty, nil}
    end
  end

  defp validate_email(email) when is_binary(email) do
    trimmed_email = String.trim(email)

    if String.match?(trimmed_email, @email_regex) do
      {:ok, trimmed_email}
    else
      {:error, @invalid_counterparty_email, trimmed_email}
    end
  end

  defp validate_email(_email), do: {:error, @no_counterparty_email, nil}
end
