defmodule Firmowid.Invoicing.SalesInvoice.EmailRecipientEligibility do
  @moduledoc """
  Finds the address a sales invoice is e-mailed to and checks that it is valid.

  An invoice goes to its counterparty's address. Without a counterparty, such as an invoice
  issued over the API, or when the counterparty has no valid address, it goes to the buyer
  address on the invoice.
  """

  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Invoicing.Counterparty
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Scope

  @no_counterparty gettext_noop("The invoice has no counterparty assigned.")
  @no_counterparty_email gettext_noop("The counterparty assigned to the invoice has no email address.")
  @invalid_counterparty_email gettext_noop("The counterparty assigned to the invoice has an invalid email address.")
  @email_regex ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  @type result :: {:ok, String.t()} | {:error, String.t(), String.t() | nil}

  @doc """
  Fetches a valid, trimmed recipient for an invoice: its counterparty's address, or else the
  buyer address on the invoice.
  """
  @spec fetch_valid_recipient_email(SalesInvoice.t(), Scope.t()) :: result()
  def fetch_valid_recipient_email(%SalesInvoice{} = invoice, scope) do
    case fetch_valid_counterparty_email(invoice.counterparty_id, scope) do
      {:ok, email} -> {:ok, email}
      {:error, _reason, _email} = error -> buyer_email(invoice.buyer_email, error)
    end
  end

  defp buyer_email(email, _counterparty_error) when is_binary(email) and email != "", do: validate_email(email)

  defp buyer_email(_email, counterparty_error), do: counterparty_error

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
