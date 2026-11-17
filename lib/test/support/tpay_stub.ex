defmodule Firmowid.Test.Support.TpayStub do
  @moduledoc """
  Test-only stand-in for Tpay, so billing tests never reach the network.

  `stub/1` answers on the `:tpay_api` `Req.Test` stub: Tpay's JWS certificates (a made-up
  root CA, intermediate CA and signing certificate), the sign-in, and every other request
  through the given function. It tells the test process about every request as
  `{:tpay_request, method, path}`. `sign/1` signs a notification body as Tpay does.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  @signing_path "/x509/notifications-jws.pem"
  @bundle_path "/x509/tpay-jws-root.pem"

  @doc """
  Gives the Tpay client made-up credentials for the test, restoring the configuration on
  exit. It changes the application environment, so its tests run with `async: false`.
  """
  @spec put_credentials(map()) :: :ok
  def put_credentials(_context) do
    config = Application.fetch_env!(:firmowid, :tpay)

    Application.put_env(
      :firmowid,
      :tpay,
      Keyword.merge(config, client_id: "test-client-id", client_secret: "test-client-secret")
    )

    on_exit(fn -> Application.put_env(:firmowid, :tpay, config) end)
  end

  @doc "Stubs Tpay: certificates and sign-in here, every other request through `api`."
  @spec stub((Plug.Conn.t() -> Plug.Conn.t())) :: :ok
  # sobelow_skip ["XSS.SendResp"]
  # A test stub answering Req.Test requests with certificates it generated itself; no browser
  # ever renders these responses.
  def stub(api \\ fn conn -> Plug.Conn.send_resp(conn, 404, "") end) do
    test = self()
    %{root: root, intermediate: intermediate, signing: signing} = chain()

    Req.Test.stub(:tpay_api, fn conn ->
      send(test, {:tpay_request, conn.method, conn.request_path})

      case {conn.method, conn.request_path} do
        {"GET", @signing_path} ->
          Plug.Conn.send_resp(conn, 200, X509.Certificate.to_pem(signing.certificate))

        {"GET", @bundle_path} ->
          pem =
            X509.Certificate.to_pem(intermediate.certificate) <>
              X509.Certificate.to_pem(root.certificate)

          Plug.Conn.send_resp(conn, 200, pem)

        {"POST", "/oauth/auth"} ->
          Req.Test.json(conn, %{"access_token" => "test-access-token"})

        _api ->
          api.(conn)
      end
    end)
  end

  @doc """
  Returns the detached JWS (`X-JWS-Signature`) of `body`, signed with the stubbed signing
  certificate, which `x5u` names on Tpay's host unless given another URL.
  """
  @spec sign(binary(), String.t()) :: String.t()
  def sign(body, x5u \\ "https://#{jws_host()}#{@signing_path}") do
    protected = encode(Jason.encode!(%{"alg" => "RS256", "x5u" => x5u}))
    signing_input = protected <> "." <> encode(body)
    signature = :public_key.sign(signing_input, :sha256, chain().signing.key)

    protected <> ".." <> encode(signature)
  end

  @doc "Returns the host Tpay serves its JWS certificates from in this environment."
  @spec jws_host() :: String.t()
  def jws_host, do: Application.fetch_env!(:firmowid, :tpay)[:jws_host]

  defp encode(binary), do: Base.url_encode64(binary, padding: false)

  # RSA keys take a while to generate, so the chain is made once per test run.
  defp chain do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        chain = new_chain()
        :persistent_term.put(__MODULE__, chain)
        chain

      chain ->
        chain
    end
  end

  defp new_chain do
    root_key = X509.PrivateKey.new_rsa(2048)
    root = X509.Certificate.self_signed(root_key, "/CN=Test Tpay Root CA", template: :root_ca)

    intermediate_key = X509.PrivateKey.new_rsa(2048)

    intermediate =
      intermediate_key
      |> X509.PublicKey.derive()
      |> X509.Certificate.new("/CN=Test Tpay Intermediate CA", root, root_key, template: :ca)

    signing_key = X509.PrivateKey.new_rsa(2048)

    signing =
      signing_key
      |> X509.PublicKey.derive()
      |> X509.Certificate.new("/CN=Test Tpay JWS", intermediate, intermediate_key)

    %{
      root: %{key: root_key, certificate: root},
      intermediate: %{key: intermediate_key, certificate: intermediate},
      signing: %{key: signing_key, certificate: signing}
    }
  end
end
