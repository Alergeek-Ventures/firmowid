defmodule Firmowid.Ash.Ksef.Services.XadesSigner do
  @moduledoc """
  Creates enveloped XAdES Baseline-B signatures for KSeF authentication.

  The signer accepts an X.509 certificate and a matching private key as PEM
  binaries. RSA keys use RSA-SHA256, while KSeF EC keys use ECDSA-SHA256 with
  the XMLDSig `R || S` fixed-width signature encoding required for P-256.

  `sign_core` provides the XAdES qualifying properties, XMLDSig builders, and
  exclusive XML canonicalization. EC signing is completed locally because
  `sign_core` 0.1.x does not yet expose an ES256 XML signing path.
  """

  alias SignCore.X509, as: SignCoreX509
  alias SignCore.XML.Builder
  alias SignCore.XML.Canonicalizer
  alias SignCore.XML.XAdES

  @ecdsa_sha256_uri "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256"
  @p256_oid {1, 2, 840, 10_045, 3, 1, 7}

  @typedoc "Stable errors returned while loading credentials or producing XAdES."
  @type error_reason ::
          :invalid_certificate
          | :invalid_private_key
          | :private_key_password_required
          | :certificate_key_mismatch
          | :certificate_expired
          | :certificate_not_yet_valid
          | :certificate_validity_unparseable
          | :rsa_key_too_short
          | :unsupported_ec_curve
          | :unsupported_key_algorithm
          | {:xml, term()}
          | term()

  @doc """
  Signs `xml` with the supplied PEM certificate and private key.

  `private_key_password` may be `nil` or an empty string for an unencrypted
  key.
  """
  @spec sign(binary(), binary(), binary(), binary() | nil) ::
          {:ok, binary()} | {:error, error_reason()}
  def sign(xml, certificate_pem, private_key_pem, private_key_password)
      when is_binary(xml) and is_binary(certificate_pem) and is_binary(private_key_pem) do
    # this whole code in a future could be replace by SingCore.XML.sign, but currently it does not support ES256
    with {:ok, certificate} <- X509.Certificate.from_pem(certificate_pem),
         :ok <- validate_certificate(certificate),
         certificate_der = X509.Certificate.to_der(certificate),
         {:ok, sign_core_certificate} <- SignCoreX509.from_der(certificate_der),
         {:ok, private_key} <- decode_private_key(private_key_pem, private_key_password),
         {:ok, algorithm} <- validate_key(private_key),
         :ok <- validate_key_pair(hd(certificate_ders), private_key, algorithm),
         {:ok, signed_xml} <- build_signature(xml, certificate_ders, leaf, private_key, algorithm) do
      {:ok, signed_xml}
    end
  end

  def sign(_xml, _certificate_pem, _private_key_pem, _private_key_password),
    do: {:error, :invalid_private_key}

    result =
      cond do
        encrypted? and is_binary(password) ->
          X509.PrivateKey.from_pem(pem, password: password)

        not encrypted? ->
          X509.PrivateKey.from_pem(pem)

        true ->
          {:error, :private_key_password_required}
      end

    case result do
      {:error, :malformed} ->
        {:error, :invalid_private_key}

      result ->
        result
    end
  end

  defp encrypted_private_key_pem?(pem),
    do:
      String.contains?(pem, "-----BEGIN ENCRYPTED PRIVATE KEY-----") or
        Regex.match?(~r/^Proc-Type:\s*4,ENCRYPTED\s*$/mi, pem)

  defp validate_certificate(certificate) do
    {:Validity, not_before, not_after} = X509.Certificate.validity(certificate)

    now = DateTime.utc_now()
    not_before = X509.DateTime.to_datetime(not_before)
    not_after = X509.DateTime.to_datetime(not_after)

    cond do
      DateTime.before?(now, not_before) -> {:error, :certificate_not_yet_valid}
      DateTime.after?(now, not_after) -> {:error, :certificate_expired}
      true -> :ok
    end
  end

  defp validate_key(
         {:RSAPrivateKey, _version, modulus, _public_exponent, _private_exponent, _prime1, _prime2, _exponent1,
          _exponent2, _coefficient, _other_prime_infos}
       ) do
    if integer_bit_size(modulus) >= 2048 do
      {:ok, :rsa}
    else
      {:error, :rsa_key_too_short}
    end
  end

  defp validate_key(
         {:ECPrivateKey, _version, _key, {:namedCurve, @p256_oid}, _public_key, _attributes}
       ),
    do: {:ok, :ec}

  defp validate_key(
         {:ECPrivateKey, _version, _key, _parameters, _public_key, _attributes}
       ),
    do: {:error, :unsupported_ec_curve}

  defp validate_key(_private_key), do: {:error, :unsupported_key_algorithm}

  defp validate_key_pair(certificate, private_key) do
    certificate_public_key = X509.Certificate.public_key(certificate)
    private_public_key = X509.PublicKey.derive(private_key)

    if private_public_key == certificate_public_key do
      :ok
    else
      {:error, :certificate_key_mismatch}
    end
  rescue
    _error -> {:error, :certificate_key_mismatch}
  end

  defp build_signature(xml, certificate_der, certificate, private_key, algorithm) do
    with {:ok, root} <- Canonicalizer.parse(xml),
         {:ok, document_canonical} <- Canonicalizer.canonicalize(root),
         signature_id = "id-" <> Builder.random_id(),
         signed_properties_id = "xades-" <> Builder.random_id(),
         {:ok, qualifying_properties} <-
           XAdES.qualifying_properties(
             signature_id: signature_id,
             signed_properties_id: signed_properties_id,
             leaf_cert: certificate,
             signing_time: DateTime.utc_now()
           ),
         {:ok, signed_properties_canonical} <-
           canonicalize_signed_properties(qualifying_properties),
         signed_info =
           build_signed_info(
             document_canonical,
             signed_properties_canonical,
             signed_properties_id,
             algorithm
           ),
         {:ok, signed_info_root} <- Canonicalizer.parse(signed_info),
         {:ok, signed_info_canonical} <- Canonicalizer.canonicalize(signed_info_root),
         {:ok, signature_value} <- sign_xml_dsig(signed_info_canonical, private_key, algorithm),
         signature =
           Builder.signature(
             signed_info,
             Base.encode64(signature_value),
             Enum.map(certificate_ders, &Base.encode64/1),
             qualifying_properties,
             signature_id: signature_id
           ) do
      splice_signature(xml, root, signature)
    end
  end

  defp canonicalize_signed_properties(qualifying_properties) do
    with {:ok, root} <- Canonicalizer.parse(qualifying_properties),
         {:ok, signed_properties} <- find_signed_properties(root) do
      Canonicalizer.canonicalize(signed_properties)
    end
  end

  defp find_signed_properties({:xmlElement, _, _, _, _, _, _, _, content, _, _, _}) do
    element =
      Enum.find(content, fn
        {:xmlElement, name, _, _, _, _, _, _, _, _, _, _} ->
          name |> Atom.to_string() |> String.ends_with?("SignedProperties")

        _ ->
          false
      end)

    case element do
      nil -> {:error, {:xml, :signed_properties_not_found}}
      element -> {:ok, element}
    end
  end

  defp build_signed_info(document, signed_properties, signed_properties_id, algorithm) do
    document_reference =
      Builder.reference(
        "",
        [Builder.transform_envelope_uri(), Builder.c14n_exclusive_uri()],
        digest(document)
      )

    properties_reference =
      Builder.reference(
        "##{signed_properties_id}",
        [Builder.c14n_exclusive_uri()],
        digest(signed_properties),
        type: Builder.reference_xades_signed_properties_type()
      )

    signed_info = Builder.signed_info([document_reference, properties_reference], :RS256)

    case algorithm do
      :rsa ->
        signed_info

      :ec ->
        String.replace(
          signed_info,
          Builder.signature_method_uri(:RS256),
          @ecdsa_sha256_uri
        )
    end
  end

  defp digest(data), do: data |> then(&:crypto.hash(:sha256, &1)) |> Base.encode64()

  defp sign_xml_dsig(data, private_key, algorithm) do
    signature = :public_key.sign(data, :sha256, private_key)

    case algorithm do
      :rsa -> {:ok, signature}
      :ec -> ecdsa_der_to_xml_dsig(signature)
    end
  end

  defp ecdsa_der_to_xml_dsig(der) do
    {:"ECDSA-Sig-Value", r, s} = :public_key.der_decode(:"ECDSA-Sig-Value", der)

    with {:ok, r} <- encode_fixed_width_integer(r, 32),
         {:ok, s} <- encode_fixed_width_integer(s, 32) do
      {:ok, r <> s}
    end
  rescue
    _error -> {:error, :invalid_ecdsa_signature}
  end

  defp take_der_value(_expected_tag, _der), do: {:error, :invalid_der}

  defp take_der_length(<<length, rest::binary>>) when length < 128,
    do: {:ok, length, rest}

  defp take_der_length(<<0x81, length, rest::binary>>), do: {:ok, length, rest}
  defp take_der_length(_der), do: {:error, :invalid_der}

    if byte_size(encoded) <= width do
      {:ok, :binary.copy(<<0>>, width - byte_size(encoded)) <> encoded}
    else
      {:error, :integer_too_wide}
    end
  end

  defp trim_leading_zeroes(<<0, rest::binary>>) when byte_size(rest) > 0,
    do: trim_leading_zeroes(rest)

  defp trim_leading_zeroes(integer), do: integer

  defp splice_signature(xml, root, signature) do
    root_name = root |> elem(1) |> Atom.to_string()
    closing_tag = "</#{root_name}>"

    case :binary.matches(xml, closing_tag) |> List.last() do
      {position, length} ->
        prefix = binary_part(xml, 0, position)
        suffix_position = position + length
        suffix = binary_part(xml, suffix_position, byte_size(xml) - suffix_position)
        {:ok, prefix <> signature <> closing_tag <> suffix}

      nil ->
        {:error, {:xml, :root_tag_not_found}}
    end
  end
end
