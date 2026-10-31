defmodule Firmowid.Ksef.Validations.ValidateSignedAuthTokenRequest do
  @moduledoc """
  Validates a signed KSeF AuthTokenRequest before certificate enrollment starts.
  """
  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Core
  alias Firmowid.Scope

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
         message: gettext_noop("is not a valid signed KSeF authentication request"),
         vars: [reason: reason]}
    end
  end

  @doc "Validates the signed AuthTokenRequest XML against the expected challenge and NIP."
  @spec validate_document(String.t(), String.t(), String.t()) ::
          :ok | {:error, :auth_token_request_mismatch | :invalid_xml | :unsafe_xml}
  def validate_document(xml, expected_challenge, organization_nip)
      when is_binary(xml) and is_binary(expected_challenge) and is_binary(organization_nip) do
    # Detect declarations in UTF-16/32 input before the parser sees a DTD.
    declarations = :binary.replace(xml, <<0>>, "", [:global])

    cond do
      Regex.match?(~r/<!DOCTYPE|<!ENTITY/i, declarations) ->
        {:error, :unsafe_xml}

      not complete_xml_encoding?(xml) ->
        {:error, :invalid_xml}

      true ->
        {:ok, {[], values}, trailing} = :erlsom.parse_sax(xml, {[], %{}}, &auth_request_event/2)

        cond do
          not Enum.all?(trailing, &(&1 in [9, 10, 13, 32])) ->
            {:error, :invalid_xml}

          auth_request_matches?(values, expected_challenge, organization_nip) ->
            :ok

          true ->
            {:error, :auth_token_request_mismatch}
        end
    end
  rescue
    _error in [ArgumentError, MatchError, FunctionClauseError] -> {:error, :invalid_xml}
  catch
    :exit, {:ucs, _reason} -> {:error, :invalid_xml}
    {:error, _reason} -> {:error, :invalid_xml}
  end

  def validate_document(_xml, _expected_challenge, _organization_nip), do: {:error, :auth_token_request_mismatch}

  defp complete_xml_encoding?(xml) do
    # SAX's trailing-data decoder discards an incomplete final code point.
    case :erlsom_lib.detect_encoding(xml) do
      {:utf8, _} -> is_list(:unicode.characters_to_list(xml, :utf8))
      {:utf16be, _} -> is_list(:unicode.characters_to_list(xml, {:utf16, :big}))
      {:utf16le, _} -> is_list(:unicode.characters_to_list(xml, {:utf16, :little}))
      {encoding, _} when encoding in [:iso_8859_1, :iso_8859_15] -> true
      _unsupported -> false
    end
  end

  defp auth_request_event({:startElement, _uri, name, _prefix, _attributes}, {stack, values}) do
    field =
      case {name, stack} do
        {~c"Challenge", _} -> :challenge
        {~c"Nip", [{~c"ContextIdentifier", _} | _]} -> :nip
        {~c"SubjectIdentifierType", _} -> :subject
        _ -> nil
      end

    values = if name == ~c"Signature", do: Map.put(values, :signature, true), else: values
    {[{name, field} | stack], values}
  end

  defp auth_request_event({event, text}, {[{_name, field} | _] = stack, values})
       when event in [:characters, :ignorableWhitespace] and not is_nil(field) do
    {stack, Map.update(values, field, [text], &[text | &1])}
  end

  defp auth_request_event({:endElement, _uri, _name, _prefix}, {[_ | stack], values}), do: {stack, values}

  defp auth_request_event(_event, state), do: state

  defp auth_request_text(values, field) do
    values |> Map.get(field, []) |> Enum.reverse() |> :unicode.characters_to_binary()
  end

  defp auth_request_matches?(values, expected_challenge, organization_nip) do
    auth_request_text(values, :challenge) == expected_challenge and
      auth_request_text(values, :nip) == organization_nip and
      auth_request_text(values, :subject) == "certificateSubject" and values[:signature] == true
  end

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
