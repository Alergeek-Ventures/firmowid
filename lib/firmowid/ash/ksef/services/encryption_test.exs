defmodule Firmowid.Ash.Ksef.Services.EncryptionTest do
  @moduledoc """
  Tests for KSeF AES-256-CBC encryption and PKCS#7 padding.

  Validates encrypt/decrypt roundtrip, padding correctness, and edge
  cases for the symmetric encryption used in KSeF invoice exchange.
  """

  use ExUnit.Case, async: true

  alias Firmowid.Ash.Ksef.Services.Encryption

  describe "AES-256-CBC encrypt/decrypt roundtrip" do
    test "roundtrips a simple message" do
      %{key: key, iv: iv} = Encryption.generate_encryption_data()
      plaintext = "Hello, KSeF!"

      encrypted = Encryption.encrypt_aes256_cbc(plaintext, key, iv)
      decrypted = Encryption.decrypt_aes256_cbc(encrypted, key, iv)

      assert decrypted == plaintext
    end

    test "roundtrips empty binary" do
      %{key: key, iv: iv} = Encryption.generate_encryption_data()
      plaintext = ""

      encrypted = Encryption.encrypt_aes256_cbc(plaintext, key, iv)
      decrypted = Encryption.decrypt_aes256_cbc(encrypted, key, iv)

      assert decrypted == plaintext
    end

    test "roundtrips exactly one block (16 bytes)" do
      %{key: key, iv: iv} = Encryption.generate_encryption_data()
      plaintext = String.duplicate("A", 16)

      encrypted = Encryption.encrypt_aes256_cbc(plaintext, key, iv)
      decrypted = Encryption.decrypt_aes256_cbc(encrypted, key, iv)

      assert decrypted == plaintext
    end

    test "roundtrips multiple blocks" do
      %{key: key, iv: iv} = Encryption.generate_encryption_data()
      plaintext = String.duplicate("B", 48)

      encrypted = Encryption.encrypt_aes256_cbc(plaintext, key, iv)
      decrypted = Encryption.decrypt_aes256_cbc(encrypted, key, iv)

      assert decrypted == plaintext
    end

    test "roundtrips non-block-aligned data (15 bytes)" do
      %{key: key, iv: iv} = Encryption.generate_encryption_data()
      plaintext = String.duplicate("C", 15)

      encrypted = Encryption.encrypt_aes256_cbc(plaintext, key, iv)
      decrypted = Encryption.decrypt_aes256_cbc(encrypted, key, iv)

      assert decrypted == plaintext
    end

    test "roundtrips large XML-like content" do
      %{key: key, iv: iv} = Encryption.generate_encryption_data()

      plaintext = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/">
        <Naglowek>
          <KodFormularza kodSystemowy="FA (3)" wersjaSchemy="1-0E">FA</KodFormularza>
        </Naglowek>
        <Podmiot1>
          <DaneIdentyfikacyjne>
            <NIP>1234567890</NIP>
            <Nazwa>Test Seller Sp. z o.o.</Nazwa>
          </DaneIdentyfikacyjne>
        </Podmiot1>
      </Faktura>
      """

      encrypted = Encryption.encrypt_aes256_cbc(plaintext, key, iv)
      decrypted = Encryption.decrypt_aes256_cbc(encrypted, key, iv)

      assert decrypted == plaintext
    end

    test "encrypted output differs from plaintext" do
      %{key: key, iv: iv} = Encryption.generate_encryption_data()
      plaintext = "sensitive invoice data"

      encrypted = Encryption.encrypt_aes256_cbc(plaintext, key, iv)

      refute encrypted == plaintext
    end

    test "encrypted output is block-aligned (multiple of 16)" do
      %{key: key, iv: iv} = Encryption.generate_encryption_data()

      for size <- [1, 7, 15, 16, 17, 31, 32, 33, 100] do
        plaintext = :crypto.strong_rand_bytes(size)
        encrypted = Encryption.encrypt_aes256_cbc(plaintext, key, iv)

        assert rem(byte_size(encrypted), 16) == 0,
               "Encrypted output for #{size}-byte input should be block-aligned, got #{byte_size(encrypted)} bytes"
      end
    end

    test "different keys produce different ciphertexts" do
      %{key: key1, iv: iv} = Encryption.generate_encryption_data()
      %{key: key2} = Encryption.generate_encryption_data()
      plaintext = "same plaintext"

      encrypted1 = Encryption.encrypt_aes256_cbc(plaintext, key1, iv)
      encrypted2 = Encryption.encrypt_aes256_cbc(plaintext, key2, iv)

      refute encrypted1 == encrypted2
    end

    test "different IVs produce different ciphertexts" do
      %{key: key, iv: iv1} = Encryption.generate_encryption_data()
      %{iv: iv2} = Encryption.generate_encryption_data()
      plaintext = "same plaintext"

      encrypted1 = Encryption.encrypt_aes256_cbc(plaintext, key, iv1)
      encrypted2 = Encryption.encrypt_aes256_cbc(plaintext, key, iv2)

      refute encrypted1 == encrypted2
    end
  end

  describe "generate_encryption_data/0" do
    test "generates 32-byte key and 16-byte IV" do
      %{key: key, iv: iv} = Encryption.generate_encryption_data()

      assert byte_size(key) == 32
      assert byte_size(iv) == 16
    end

    test "generates unique keys on each call" do
      %{key: key1} = Encryption.generate_encryption_data()
      %{key: key2} = Encryption.generate_encryption_data()

      refute key1 == key2
    end
  end
end
