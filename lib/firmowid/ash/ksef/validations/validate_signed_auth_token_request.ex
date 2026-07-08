defmodule Firmowid.Ash.Ksef.Validations.ValidateSignedAuthTokenRequest do
  @moduledoc """
  Validates a signed KSeF AuthTokenRequest before certificate enrollment starts.
  """
  use Ash.Resource.Validation

  import SweetXml

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Scope

  @impl true
  def validate(changeset, _opts, context) do
    xml = Ash.Changeset.get_argument(changeset, :signed_auth_token_request)
    challenge = Ash.Changeset.get_argument(changeset, :challenge)
    organization_nip = organization_nip!(changeset, context)

    case validate_document(xml, challenge, organization_nip) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         field: :signed_auth_token_request,
         message: "nie jest poprawnym podpisanym żądaniem uwierzytelnienia KSeF",
         vars: [reason: reason]}
    end
  end

  @doc "Validates the signed AuthTokenRequest XML against the expected challenge and NIP."
  @spec validate_document(String.t(), String.t(), String.t()) ::
          :ok | {:error, :auth_token_request_mismatch | :invalid_xml | :unsafe_xml}
  def validate_document(xml, expected_challenge, organization_nip)
      when is_binary(xml) and is_binary(expected_challenge) and is_binary(organization_nip) do
    valid_document_type? = not Regex.match?(~r/<!DOCTYPE|<!ENTITY/i, xml)

    if valid_document_type? do
      document = SweetXml.parse(xml, dtd: :none, quiet: true)

      with ^expected_challenge <- xpath(document, ~x"//*[local-name()='Challenge']/text()"s),
           ^organization_nip <-
             xpath(
               document,
               ~x"//*[local-name()='ContextIdentifier']/*[local-name()='Nip']/text()"s
             ),
           "certificateSubject" <-
             xpath(document, ~x"//*[local-name()='SubjectIdentifierType']/text()"s),
           [_signature | _] <- xpath(document, ~x"//*[local-name()='Signature']"l) do
        :ok
      else
        _mismatch -> {:error, :auth_token_request_mismatch}
      end
    else
      {:error, :unsafe_xml}
    end
  catch
    :exit, _reason -> {:error, :invalid_xml}
  end

  def validate_document(_xml, _expected_challenge, _organization_nip), do: {:error, :auth_token_request_mismatch}

  defp organization_nip!(changeset, context) do
    scope = %Scope{
      actor: context.actor,
      tenant: changeset.tenant
    }

    changeset.tenant
    |> Core.get_organization!(scope: scope)
    |> Map.fetch!(:nip)
  end
end
