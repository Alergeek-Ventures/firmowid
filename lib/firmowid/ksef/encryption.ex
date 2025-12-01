defmodule Firmowid.Ksef.Encryption do
  @moduledoc false
  alias Firmowid.Ksef.ApiClient

  def decrypt_aes256_cbc(encrypted_data, key, iv) do
    :aes_256_cbc
    |> :crypto.crypto_one_time(key, iv, encrypted_data, encrypt: false)
    |> unpad_pkcs7()
  end

  defp unpad_pkcs7(data) do
    <<pad>> = binary_part(data, byte_size(data), -1)
    binary_part(data, 0, byte_size(data) - pad)
  end

  def generate_encryption_data do
    key = :crypto.strong_rand_bytes(32)
    iv = :crypto.strong_rand_bytes(16)

    %{key: key, iv: iv}
  end

  def encrypt_with_rsa_public_key(data) do
    encrypt_with_certificate(data, ApiClient.ksef_public_key())
  end

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
