defmodule Firmowid.Ash.Ksef.Services.Encryption do
  @moduledoc """
  Cryptographic operations for KSeF invoice exchange.

  Provides AES-256-CBC symmetric encryption (with PKCS#7 padding) for invoice
  XML payloads, and RSA public-key encryption for symmetric key transport.

  KSeF requires:
  - Invoice XML encrypted with AES-256-CBC before submission
  - The AES key itself encrypted with KSeF's RSA public key
  - Separate RSA keys for token encryption vs symmetric key encryption
  """
  alias Firmowid.Ash.Ksef.Services.ApiClient

  @doc """
  Encrypts data with AES-256-CBC and PKCS#7 padding.
  Used for encrypting invoice XML before sending to KSeF.
  """
  @spec encrypt_aes256_cbc(binary(), binary(), binary()) :: binary()
  def encrypt_aes256_cbc(data, key, iv) do
    data
    |> pad_pkcs7()
    |> then(&:crypto.crypto_one_time(:aes_256_cbc, key, iv, &1, encrypt: true))
  end

  @doc "Decrypts AES-256-CBC encrypted data and removes PKCS#7 padding."
  @spec decrypt_aes256_cbc(binary(), binary(), binary()) :: binary()
  def decrypt_aes256_cbc(encrypted_data, key, iv) do
    :aes_256_cbc
    |> :crypto.crypto_one_time(key, iv, encrypted_data, encrypt: false)
    |> unpad_pkcs7()
  end

  defp unpad_pkcs7(data) when byte_size(data) > 0 do
    <<pad>> = binary_part(data, byte_size(data), -1)

    # Validate padding value is in valid range
    if pad < 1 or pad > 16 or pad > byte_size(data) do
      raise "Invalid PKCS#7 padding"
    end

    # Verify all padding bytes have the same value
    data_len = byte_size(data)
    padding_bytes = binary_part(data, data_len - pad, pad)

    if padding_bytes != :binary.copy(<<pad>>, pad) do
      raise "Invalid PKCS#7 padding bytes"
    end

    binary_part(data, 0, data_len - pad)
  end

  defp pad_pkcs7(data) do
    block_size = 16
    pad_len = block_size - rem(byte_size(data), block_size)
    data <> :binary.copy(<<pad_len>>, pad_len)
  end

  @doc "Generates a random AES-256 key (32 bytes) and IV (16 bytes) for symmetric encryption."
  @spec generate_encryption_data() :: %{key: binary(), iv: binary()}
  def generate_encryption_data do
    key = :crypto.strong_rand_bytes(32)
    iv = :crypto.strong_rand_bytes(16)

    %{key: key, iv: iv}
  end

  @doc "Encrypts data with KSeF's token encryption RSA public key (OAEP SHA-256)."
  @spec encrypt_with_rsa_public_key(binary()) :: binary()
  def encrypt_with_rsa_public_key(data) do
    encrypt_with_certificate(data, ApiClient.ksef_public_key())
  end

  @doc "Encrypts data with KSeF's symmetric key encryption RSA public key (OAEP SHA-256)."
  @spec encrypt_symmetric_key(binary()) :: binary()
  def encrypt_symmetric_key(data) do
    encrypt_with_certificate(data, ApiClient.symmetric_key_public_key())
  end

  defp encrypt_with_certificate(data, certificate) do
    {:RSAPublicKey, n, e} = X509.Certificate.public_key(certificate)

    :crypto.public_encrypt(
      :rsa,
      data,
      [e, n],
      [
        {:rsa_padding, :rsa_pkcs1_oaep_padding},
        {:rsa_mgf1_md, :sha256},
        {:rsa_oaep_md, :sha256},
        {:rsa_oaep_label, <<>>}
      ]
    )
  end
end
