defmodule Firmowid.Ash.Ksef.Calculations.CredentialExpiresOn do
  @moduledoc """
  Determines the KSeF credential expiration date.

  KSeF tokens expire on 1 January 2027. Certificate expiration is read from
  the X.509 `notAfter` value stored in the encrypted credential payload.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:auth_type, :credentials]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &expiration_date/1)
  end

  defp expiration_date(%{auth_type: :token}), do: ~D[2027-01-01]

  defp expiration_date(%{auth_type: auth_type, credentials: credentials})
       when auth_type in [:certificate, :generated_certificate] do
    with {:ok, %{"certificate" => certificate_pem}} <- Jason.decode(credentials),
         {:ok, certificate} <- X509.Certificate.from_pem(certificate_pem),
         {:Validity, _not_before, not_after} <- X509.Certificate.validity(certificate) do
      not_after
      |> X509.DateTime.to_datetime()
      |> DateTime.to_date()
    else
      _error -> nil
    end
  end
end
