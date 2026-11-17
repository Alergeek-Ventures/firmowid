defmodule Firmowid.Billing.Tpay.SignatureTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Firmowid.Billing.Tpay.Signature
  alias Firmowid.Test.Support.TpayStub

  @body ~s({"type":"tokenization","data":{"tokenizationId":"TOK-1"}})

  test "accepts Tpay's signature of the exact body and rejects a tampered body or a foreign certificate" do
    TpayStub.stub()

    assert :ok = Signature.verify(@body, TpayStub.sign(@body))
    assert {:error, :invalid_signature} = Signature.verify(@body <> " ", TpayStub.sign(@body))

    # A certificate on Tpay's host that Tpay's CA did not issue.
    foreign_key = X509.PrivateKey.new_rsa(2048)
    foreign = X509.Certificate.self_signed(foreign_key, "/CN=Not Tpay")

    TpayStub.stub(fn conn -> Plug.Conn.send_resp(conn, 200, X509.Certificate.to_pem(foreign)) end)

    protected =
      Base.url_encode64(~s({"alg":"RS256","x5u":"https://#{TpayStub.jws_host()}/x509/other.pem"}),
        padding: false
      )

    signing_input = protected <> "." <> Base.url_encode64(@body, padding: false)

    signature =
      Base.url_encode64(:public_key.sign(signing_input, :sha256, foreign_key), padding: false)

    assert {:error, :invalid_signature} = Signature.verify(@body, protected <> ".." <> signature)
  end

  test "rejects a certificate URL outside Tpay's host without downloading it" do
    TpayStub.stub()
    host = TpayStub.jws_host()

    for x5u <- [
          "https://#{host}.attacker.example/x509/notifications-jws.pem",
          "https://attacker.example/#{host}/x509/notifications-jws.pem",
          "https://#{host}@attacker.example/x509/notifications-jws.pem",
          "http://#{host}/x509/notifications-jws.pem"
        ] do
      assert {:error, :invalid_signature} = Signature.verify(@body, TpayStub.sign(@body, x5u))
    end

    refute_received {:tpay_request, _method, _path}
  end
end
