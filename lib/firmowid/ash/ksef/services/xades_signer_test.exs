defmodule Firmowid.Ash.Ksef.Services.XadesSignerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Firmowid.Ash.Ksef.Services.XadesSigner
  alias SignCore.XML.Builder
  alias SignCore.XML.Canonicalizer
  alias X509.Certificate.Validity

  @password "test-private-key-password"
  @xml """
  <?xml version="1.0" encoding="utf-8"?>
  <AuthTokenRequest xmlns="http://ksef.mf.gov.pl/auth/token/2.0">
    <Challenge>test-challenge</Challenge>
    <ContextIdentifier><Nip>6161525811</Nip></ContextIdentifier>
    <SubjectIdentifierType>certificateSubject</SubjectIdentifierType>
  </AuthTokenRequest>
  """

  setup_all do
    rsa = credential_fixture(:rsa)
    ec = credential_fixture(:ec)
    other_rsa = credential_fixture(:rsa)

    %{rsa: rsa, ec: ec, other_rsa: other_rsa}
  end

  test "creates a cryptographically valid RSA-SHA256 XAdES signature", %{rsa: credential} do
    assert {:ok, signed_xml} =
             XadesSigner.sign(
               @xml,
               credential.certificate_pem,
               credential.private_key_pem,
               @password
             )

    assert signed_xml =~ "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
    assert_xades_structure(signed_xml)

    {signed_info, signature} = signature_parts(signed_xml)
    public_key = X509.Certificate.public_key(credential.certificate)

    assert :public_key.verify(signed_info, :sha256, signature, public_key)
  end

  test "creates a cryptographically valid P-256 ECDSA XAdES signature", %{ec: credential} do
    assert {:ok, signed_xml} =
             XadesSigner.sign(
               @xml,
               credential.certificate_pem,
               credential.private_key_pem,
               @password
             )

    assert signed_xml =~ "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256"
    assert_xades_structure(signed_xml)

    {signed_info, signature} = signature_parts(signed_xml)
    assert byte_size(signature) == 64

    public_key = X509.Certificate.public_key(credential.certificate)
    assert :public_key.verify(signed_info, :sha256, xml_dsig_to_ecdsa_der(signature), public_key)
  end

  test "accepts CRLF PEM input without a trailing newline", %{ec: credential} do
    certificate = credential.certificate_pem |> String.replace("\n", "\r\n") |> String.trim()
    private_key = credential.private_key_pem |> String.replace("\n", "\r\n") |> String.trim()

    assert {:ok, _signed_xml} = XadesSigner.sign(@xml, certificate, private_key, @password)
  end

  test "returns a stable error for an incorrect private key password", %{ec: credential} do
    assert {:error, :invalid_private_key} =
             XadesSigner.sign(
               @xml,
               credential.certificate_pem,
               credential.private_key_pem,
               "incorrect"
             )
  end

  test "rejects a private key that does not match the certificate", %{
    rsa: credential,
    other_rsa: other_credential
  } do
    assert {:error, :certificate_key_mismatch} =
             XadesSigner.sign(
               @xml,
               credential.certificate_pem,
               other_credential.private_key_pem,
               @password
             )
  end

  test "rejects malformed certificates", %{rsa: credential} do
    assert {:error, _} =
             XadesSigner.sign(@xml, "not a certificate", credential.private_key_pem, @password)
  end

  test "rejects expired certificates" do
    expired =
      credential_fixture(
        :ec,
        validity:
          Validity.new(
            DateTime.shift(DateTime.utc_now(), day: -1),
            DateTime.shift(DateTime.utc_now(), minute: -1)
          )
      )

    assert {:error, :certificate_expired} =
             XadesSigner.sign(
               @xml,
               expired.certificate_pem,
               expired.private_key_pem,
               @password
             )
  end

  test "rejects certificates that are not valid yet" do
    not_yet_valid =
      credential_fixture(
        :ec,
        validity:
          Validity.new(
            DateTime.shift(DateTime.utc_now(), minute: 1),
            DateTime.shift(DateTime.utc_now(), day: 1)
          )
      )

    assert {:error, :certificate_not_yet_valid} =
             XadesSigner.sign(
               @xml,
               not_yet_valid.certificate_pem,
               not_yet_valid.private_key_pem,
               @password
             )
  end

  defp credential_fixture(type, opts \\ []) do
    private_key =
      case type do
        :rsa -> X509.PrivateKey.new_rsa(2048)
        :ec -> X509.PrivateKey.new_ec(:secp256r1)
      end

    certificate =
      X509.Certificate.self_signed(
        private_key,
        "/C=PL/O=Firmowid Test/CN=KSeF Test",
        validity: Keyword.get(opts, :validity, Validity.days_from_now(1))
      )

    %{
      certificate: certificate,
      certificate_pem: X509.Certificate.to_pem(certificate),
      private_key_pem: encrypted_pkcs8_pem(private_key)
    }
  end

  defp encrypted_pkcs8_pem(private_key) do
    {_jwk, encrypted_pem} =
      private_key
      |> JOSE.JWK.from_key()
      |> then(&JOSE.JWK.to_pem(@password, &1))

    encrypted_pem
  end

  defp assert_xades_structure(signed_xml) do
    assert signed_xml =~ "<ds:Signature "
    assert signed_xml =~ "<xades:QualifyingProperties "
    assert signed_xml =~ "<xades:SignedProperties "
    assert signed_xml =~ "<xades:SigningTime>"
    assert signed_xml =~ "<xades:SigningCertificateV2>"
    assert signed_xml =~ Builder.reference_xades_signed_properties_type()
    assert signed_xml =~ Builder.transform_envelope_uri()
  end

  defp signature_parts(signed_xml) do
    [_, signed_info_xml] = Regex.run(~r/(<ds:SignedInfo.*?<\/ds:SignedInfo>)/s, signed_xml)

    [_, signature_base64] =
      Regex.run(~r/<ds:SignatureValue>([^<]+)<\/ds:SignatureValue>/, signed_xml)

    {:ok, signed_info_root} = Canonicalizer.parse(signed_info_xml)
    {:ok, signed_info} = Canonicalizer.canonicalize(signed_info_root)

    {signed_info, Base.decode64!(signature_base64)}
  end

  defp xml_dsig_to_ecdsa_der(<<r::binary-size(32), s::binary-size(32)>>) do
    sequence = der_integer(r) <> der_integer(s)
    <<0x30, byte_size(sequence), sequence::binary>>
  end

  defp der_integer(integer) do
    integer = trim_zeroes(integer)
    integer = if :binary.first(integer) >= 0x80, do: <<0, integer::binary>>, else: integer
    <<0x02, byte_size(integer), integer::binary>>
  end

  defp trim_zeroes(<<0, rest::binary>>) when byte_size(rest) > 1, do: trim_zeroes(rest)
  defp trim_zeroes(integer), do: integer
end
