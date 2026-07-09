defmodule Firmowid.Ash.Ksef.CredentialMetadata do
  @moduledoc """
  Derives non-sensitive metadata from stored KSeF certificate credentials.
  """

  @doc """
  Returns the normalized hexadecimal serial number for a certificate credential.
  """
  @spec certificate_serial_number(map()) :: String.t()
  def certificate_serial_number(%{auth_type: auth_type, credentials: credentials})
      when auth_type in [:certificate, :generated_certificate] do
    credentials
    |> Jason.decode!()
    |> Map.fetch!("certificate")
    |> X509.Certificate.from_pem!()
    |> X509.Certificate.serial()
    |> Integer.to_string(16)
    |> String.upcase()
    |> String.pad_leading(16, "0")
  end

  @doc """
  Returns the expiration date for a KSeF credential.
  """
  @spec expires_on(map()) :: Date.t() | nil
  def expires_on(%{auth_type: :token}), do: ~D[2027-01-01]

  def expires_on(%{auth_type: auth_type, credentials: credentials})
      when auth_type in [:certificate, :generated_certificate] and is_binary(credentials) do
    with {:ok, %{"certificate" => certificate}} <- Jason.decode(credentials),
         {:Validity, _not_before, not_after} <-
           certificate |> X509.Certificate.from_pem!() |> X509.Certificate.validity() do
      not_after
      |> X509.DateTime.to_datetime()
      |> DateTime.to_date()
    else
      _ -> nil
    end
  end

  def expires_on(%{credentials: nil}), do: nil
end
