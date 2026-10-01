defmodule FirmowidWeb.Landing.Views.PrivacyPolicy do
  @moduledoc """
  Privacy Policy (Polityka Prywatności) page for Firmowid.

  Public page accessible at `/polityka-prywatnosci`. Contains the full
  RODO-compliant privacy policy in Polish, covering data collection,
  processing purposes, third-party processors, user rights, and cookies.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.Landing.Components.LegalPage, only: [legal_page: 1]

  @legal_entity Application.compile_env!(:firmowid, :legal_entity)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Privacy Policy"),
       meta_description:
         gettext("Firmowid's Privacy Policy describes the processing of data, cookies, and users' rights."),
       public_marketing?: true,
       legal_entity: @legal_entity
     ), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.legal_page>
      <h1 class="text-4xl font-bold">{gettext("Privacy Policy")}</h1>
      <p class="text-sm text-neutral-500">
        {gettext("Last updated: September 30, 2026")}
      </p>

      <h2>{gettext("§1. Data Controller")}</h2>
      <p>
        {gettext("The data controller is")} <strong>{@legal_entity.name}</strong>
        {gettext("with its registered office at")} {@legal_entity.headquarters_location}, {@legal_entity.address}, {gettext(
          "entered in the Register of Entrepreneurs maintained by the XI Commercial Division of the National Court Register of the District Court for Kraków-Śródmieście in Kraków under number"
        )} KRS: {@legal_entity.krs}, NIP: {@legal_entity.nip}, REGON: {@legal_entity.regon} {gettext(
          "(hereinafter: the “Controller” or “Alergeek Ventures”)."
        )}
      </p>
      <p>
        {gettext("Contact regarding personal data protection:")}
        <FirmowidWeb.DesignSystem.Components.Link.link
          kind="unstyled"
          mailto="contact@alergeek.ventures"
          class="text-orange-700 hover:underline"
        >
          contact@alergeek.ventures
        </FirmowidWeb.DesignSystem.Components.Link.link>
      </p>

      <h2>{gettext("§2. What data we collect")}</h2>
      <p>
        {gettext(
          "When using the Firmowid service, we process the following categories of personal data:"
        )}
      </p>
      <ul>
        <li>
          <strong>{gettext("Account data")}</strong> {gettext(
            "— first name, last name, email address, and authentication data (including through Google OAuth)."
          )}
        </li>
        <li>
          <strong>{gettext("Organization data")}</strong> {gettext(
            "— company name, tax identification number, registered office address, and contact details."
          )}
        </li>
        <li>
          <strong>{gettext("Invoicing data")}</strong> {gettext(
            "— contents of sales and purchase invoices, and counterparty data."
          )}
        </li>
        <li>
          <strong>{gettext("Document analysis data")}</strong> {gettext(
            "— document files uploaded by the user and data extracted from them, in particular invoice, seller, and invoice line-item data."
          )}
        </li>
        <li>
          <strong>{gettext("Bank account data")}</strong> {gettext(
            "— account and transaction information synchronized through GoCardless (Open Banking)."
          )}
        </li>
        <li>
          <strong>{gettext("Working time records")}</strong> {gettext(
            "— working time entries and project assignments."
          )}
        </li>
        <li>
          <strong>{gettext("Technical data")}</strong> {gettext(
            "— IP address, browser information, and session data."
          )}
        </li>
      </ul>

      <h2>{gettext("§3. Purpose and legal basis for processing")}</h2>
      <p>
        {gettext(
          "We process personal data for the following purposes and on the following legal bases:"
        )}
      </p>
      <ul>
        <li>
          <strong>{gettext("Performance of the contract")}</strong> {gettext(
            "(Article 6(1)(b) GDPR) — processing is necessary to provide the Firmowid service, including maintaining the user account, issuing invoices, synchronizing bank accounts, recording working time, and managing the organization."
          )}
        </li>
        <li>
          <strong>{gettext("The Controller’s legitimate interest")}</strong> {gettext(
            "(Article 6(1)(f) GDPR) — service analytics and quality improvement, security, fraud detection, and handling support requests."
          )}
        </li>
        <li>
          <strong>{gettext("Consent")}</strong> {gettext(
            "(Article 6(1)(a) GDPR) — optional marketing communications, analytics cookies, and session recording. Consent may be withdrawn at any time."
          )}
        </li>
      </ul>
      <p>
        {gettext(
          "Information about account creation and use of selected features helps us better understand users’ needs and develop Firmowid. For this purpose, we use PostHog. This information is linked to the user account and, when organization features are used, to the organization as well. Analytics does not include invoice contents or counterparty data. This analytics activity does not use analytics cookies and is independent of cookie settings."
        )}
      </p>

      <h2>{gettext("§4. Processors")}</h2>
      <p>
        {gettext(
          "The following providers support the operation of Firmowid. As part of their services, they process information needed to achieve the purposes described:"
        )}
      </p>
      <ul>
        <li>
          <strong>OVH SAS</strong> {gettext(
            "(2 rue Kellermann, 59100 Roubaix, France) — hosting the application infrastructure and storing files in Object Storage. Data is stored within the European Union."
          )}
        </li>
        <li>
          <strong>PostHog Inc.</strong> {gettext(
            "(2261 Market Street, #4008, San Francisco, CA 94114, USA) — analytics of Service usage, including the activities described in §3. We use PostHog services provided in the European Union."
          )}
        </li>
        <li>
          <strong>Functional Software, Inc. (Sentry)</strong> {gettext(
            "(45 Fremont Street, 8th Floor, San Francisco, CA 94105, USA) — monitoring Service errors, failures, and performance. Reports may contain technical data and context necessary to diagnose an error. With consent, they may also include session recordings that help identify the cause of an error."
          )}
        </li>
        <li>
          <strong>Plus Five Five, Inc. (Resend)</strong> {gettext(
            "(2261 Market Street #5039, San Francisco, CA 94114, USA) — email handling: sending transactional messages, receiving messages addressed to the Service, and handling attachments, including documents submitted for processing."
          )}
        </li>
        <li>
          <strong>Google Ireland Limited</strong> {gettext(
            "(Gordon House, Barrow Street, Dublin 4, Ireland) — user authentication through Google OAuth. For this purpose, we receive profile data shared during sign-in, in particular the email address, first and last name, and Google account identifier."
          )}
        </li>
        <li>
          <strong>GoCardless Limited</strong> {gettext(
            "(Sutton Yard, 65 Goswell Road, London, EC1V 7EN, United Kingdom) — Open Banking services, namely authenticating the connection to a bank account and retrieving account and transaction information. GoCardless acts as an independent controller to the extent required to provide regulated banking services."
          )}
        </li>
        <li>
          <strong>Reducto, Inc.</strong>
          {gettext(
            "(77 Geary Street, San Francisco, CA 94108, USA) — analysis of document files uploaded by the user, including invoices and contracts, as well as OCR and extraction of data needed for Service features. As part of this service, Reducto processes the document contents or a URL enabling it to retrieve the document."
          )}
        </li>
        <li>
          <strong>OpenAI Ireland Limited</strong>
          {gettext(
            "(1st Floor, The Liffey Trust Centre, 117-126 Sheriff Street Upper, Dublin 1, D01 YC43, Ireland) — automatically generating descriptions of purchase invoices, standardizing seller names, and supporting assistant and invoice-to-transaction matching features. For these features, OpenAI processes data extracted from invoices, in particular seller data, invoice line items and amounts, as well as information provided by the user."
          )}
        </li>
      </ul>
      <h2>{gettext("§5. Data retention")}</h2>
      <p>
        {gettext("Personal data is stored for the duration of your use of the Firmowid service.")}
      </p>
      <p>
        {gettext(
          "After the user deletes an account or an organization is deleted, the Controller immediately attempts to delete the associated data from the database. Full cleanup of data in the Service’s systems, including storage (Object Storage), may take up to 30 days. If an external service error occurs, deleting objects from storage may require manual intervention. Deletion does not cover data whose continued retention is required by law or data retained by external providers over which the Controller has no direct control; such data may be subject to those providers’ retention periods. Residual data may remain in the logs of external services (PostHog, Resend) for their standard retention periods."
        )}
      </p>

      <h2>{gettext("§6. User rights")}</h2>
      <p>{gettext("Under the GDPR, you have the following rights:")}</p>
      <ul>
        <li>{gettext("Right of access to data (Article 15 GDPR)")}</li>
        <li>{gettext("Right to rectification of data (Article 16 GDPR)")}</li>
        <li>{gettext("Right to erasure of data — the “right to be forgotten” (Article 17 GDPR)")}</li>
        <li>{gettext("Right to restriction of processing (Article 18 GDPR)")}</li>
        <li>{gettext("Right to data portability (Article 20 GDPR)")}</li>
        <li>{gettext("Right to object to processing (Article 21 GDPR)")}</li>
        <li>
          {gettext(
            "Right to lodge a complaint with the supervisory authority — the President of the Personal Data Protection Office (ul. Stawki 2, 00-193 Warsaw)"
          )}
        </li>
      </ul>
      <p>
        {gettext("To exercise the above rights, please contact us:")}
        <FirmowidWeb.DesignSystem.Components.Link.link
          kind="unstyled"
          mailto="contact@alergeek.ventures"
          class="text-orange-700 hover:underline"
        >
          contact@alergeek.ventures
        </FirmowidWeb.DesignSystem.Components.Link.link>
      </p>

      <h2>{gettext("§7. Cookies")}</h2>
      <p>{gettext("Firmowid uses the following cookies:")}</p>
      <ul>
        <li>
          <strong>{gettext("Necessary cookies (session)")}</strong> {gettext(
            "— required for the application to function properly, to maintain the user session, and to protect against CSRF attacks. They do not require consent."
          )}
        </li>
        <li>
          <strong>{gettext("Analytics cookies (PostHog)")}</strong> {gettext(
            "— help analyze use of the Service in the browser. They are optional and are stored after consent. Before a choice is made, analytics does not persist data in the browser or link it to an account. Choosing “Reject” disables this form of analytics. Cookie settings apply to browser analytics; account-related analytics is described in §3."
          )}
        </li>
        <li>
          <strong>{gettext("Error monitoring (Sentry)")}</strong> {gettext(
            "— operates continuously to ensure the security and reliability of the Service. With consent, we may additionally enable session recording in the browser, which helps reproduce the steps leading to an error."
          )}
        </li>
        <li>
          <strong>{gettext("Preference cookie (cookie_consent)")}</strong> {gettext(
            "— stores information about consent to or refusal of analytics cookies. Validity: 1 year."
          )}
        </li>
      </ul>

      <h2>{gettext("§8. Changes to the Privacy Policy")}</h2>
      <p>
        {gettext(
          "The Controller reserves the right to amend this Privacy Policy. Users will be informed of any changes by publication of the updated version on the page"
        )}
        <FirmowidWeb.DesignSystem.Components.Link.link
          kind="unstyled"
          navigate={~p"/polityka-prywatnosci"}
          class="text-orange-700 hover:underline"
        >
          firmowid.pl/polityka-prywatnosci
        </FirmowidWeb.DesignSystem.Components.Link.link>
        {gettext("together with the date of the latest update.")}
      </p>
    </.legal_page>
    """
  end
end
