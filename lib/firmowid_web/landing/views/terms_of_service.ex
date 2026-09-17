defmodule FirmowidWeb.Landing.Views.TermsOfService do
  @moduledoc """
  Terms of Service (Regulamin) page for Firmowid.

  Public page accessible at `/regulamin`. Contains the full Terms of Service
  in Polish, covering service scope, user accounts, liability limitations,
  pricing, data handling, and governing law.
  """
  use FirmowidWeb, :live_view
  use Gettext, backend: FirmowidWeb.Core.Gettext

  import FirmowidWeb.Landing.Components.LegalPage, only: [legal_page: 1]

  @legal_entity Application.compile_env!(:firmowid, :legal_entity)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Terms of Service"),
       meta_description:
         gettext(
           "Firmowid's Terms of Service define the rules for using its invoicing, KSeF, banking, and work-tracking service."
         ),
       public_marketing?: true,
       legal_entity: @legal_entity
     ), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.legal_page>
      <h1 class="text-4xl font-bold">{gettext("Terms of Service")}</h1>
      <p class="text-sm text-neutral-500">
        {gettext("Last updated: September 8, 2026")}
      </p>

      <h2>{gettext("§1. General provisions")}</h2>
      <p>
        {gettext(
          "These Terms of Service set out the rules for using the Firmowid online service (hereinafter: the “Service”), available at"
        )} <FirmowidWeb.DesignSystem.Components.Link.link
          kind="unstyled"
          external="https://firmowid.pl"
          class="text-orange-700 hover:underline"
        >firmowid.pl</FirmowidWeb.DesignSystem.Components.Link.link>.
      </p>
      <p>
        {gettext("The service provider is")} <strong>{@legal_entity.name}</strong>
        {gettext("with its registered office at")} {@legal_entity.headquarters_location}, {@legal_entity.address}, {gettext(
          "entered in the Register of"
        )}
        {gettext(
          "Entrepreneurs maintained by the XI Commercial Division of the National Court Register of the District Court for Kraków-Śródmieście in Kraków under number"
        )} KRS: {@legal_entity.krs}, NIP: {@legal_entity.nip}, REGON: {@legal_entity.regon} {gettext(
          "(hereinafter: the “Service Provider” or “Alergeek Ventures”)."
        )}
      </p>
      <p>
        {gettext("The Service includes, in particular:")}
      </p>
      <ul>
        <li>
          {gettext("Issuing, managing, and storing sales and purchase invoices")}
        </li>
        <li>{gettext("Synchronizing and viewing company bank accounts (Open Banking)")}</li>
        <li>{gettext("Automatically matching invoices to bank transactions")}</li>
        <li>{gettext("Recording working time and managing projects")}</li>
        <li>{gettext("Managing employees, leave, and contracts")}</li>
        <li>{gettext("Managing counterparties and organization data")}</li>
        <li>
          {gettext(
            "Other functions related to conducting business, introduced as the Service develops"
          )}
        </li>
      </ul>

      <h2>{gettext("§2. User account")}</h2>
      <p>
        {gettext("Using the Service requires creating a user account. Registration")}
        {gettext("is possible using an email address or a Google account (OAuth).")}
      </p>
      <p>
        {gettext(
          "The User undertakes to provide accurate information and keep login credentials confidential. The User is responsible for all"
        )}
        {gettext("actions performed through their account.")}
      </p>

      <h2>{gettext("§3. Nature of the Service")}</h2>
      <p>
        {gettext("Firmowid is a tool supporting the conduct of business activities.")}
      </p>
      <p>
        <strong>
          {gettext("The Service does not constitute tax, accounting, or legal advice.")}
        </strong>
        {gettext(
          "The User is solely responsible for the accuracy of entered data, the content of generated documents, and their compliance with applicable law."
        )}
      </p>
      <p>
        {gettext(
          "The Service Provider does not verify the substantive correctness of data entered by users and is not responsible for consequences arising from inaccuracies in that data."
        )}
      </p>

      <h2>{gettext("§4. Availability and limitation of liability")}</h2>
      <p>
        {gettext("The Service is provided on an “as is” basis (")}<em>as is</em>{gettext(
          "). The Service Provider makes efforts to ensure the continuity and proper operation of the Service, but does not guarantee uninterrupted availability or the absence of errors."
        )}
      </p>
      <p>
        <strong>
          {gettext(
            "To the fullest extent permitted by applicable law, Alergeek Ventures is not liable for any damages arising from the use of or inability to use the Service, including in particular direct, indirect, incidental, consequential damages, lost profits, data loss, business interruption, or any other financial or non-financial losses."
          )}
        </strong>
      </p>
      <p>
        {gettext(
          "The Service Provider reserves the right to suspend the Service temporarily for maintenance, updates, or repairs."
        )}
      </p>

      <h2>{gettext("§5. Pricing")}</h2>
      <p>
        {gettext(
          "The Service is available on a freemium model, comprising a free basic plan and paid subscription plans with an expanded range of features."
        )}
      </p>
      <p>
        {gettext(
          "The current pricing is available on the Service website. The Service Provider reserves the right to change the pricing with at least 30 days’ notice. A pricing change does not affect subscription periods that have already been paid for."
        )}
      </p>

      <h2>{gettext("§6. Personal data protection")}</h2>
      <p>
        {gettext("The rules for processing personal data are set out in")} <FirmowidWeb.DesignSystem.Components.Link.link
          kind="unstyled"
          navigate={~p"/polityka-prywatnosci"}
          class="text-orange-700 hover:underline"
        >
            {gettext("the Privacy Policy")}</FirmowidWeb.DesignSystem.Components.Link.link>{gettext(
          ", which forms an integral part of these Terms of Service."
        )}
      </p>

      <h2>{gettext("§7. Account deletion")}</h2>
      <p>
        {gettext(
          "The User may delete their account at any time. After the account is deleted, the User’s data is promptly removed from the Service database and storage."
        )}
      </p>
      <p>
        {gettext(
          "Residual data may remain in the logs of external services (analytics, email) for their standard retention periods, as described in the Privacy Policy."
        )}
      </p>

      <h2>{gettext("§8. Termination of the agreement")}</h2>
      <p>
        {gettext(
          "The Service Provider reserves the right to suspend or delete a user account in the event of a breach of these Terms of Service, actions to the detriment of the Service or other users, or use of the Service in an unlawful manner."
        )}
      </p>

      <h2>{gettext("§9. Changes to the Terms of Service")}</h2>
      <p>
        {gettext(
          "The Service Provider reserves the right to amend these Terms of Service. Users will be informed of planned changes in good time by electronic means or through a notice in the Service."
        )}
      </p>
      <p>
        {gettext(
          "Continued use of the Service after changes to the Terms of Service take effect constitutes acceptance of those changes. If the User does not accept them, they may delete their account before the changes take effect."
        )}
      </p>

      <h2>{gettext("§10. Governing law and dispute resolution")}</h2>
      <p>
        {gettext(
          "These Terms of Service are governed by Polish law. Any disputes arising from the use of the Service will be resolved by the court having jurisdiction over the Service Provider’s registered office, namely a court in Kraków."
        )}
      </p>

      <h2>{gettext("§11. Contact")}</h2>
      <p>
        {gettext("Any questions regarding the Terms of Service or the Service should be sent to:")}
        <FirmowidWeb.DesignSystem.Components.Link.link
          kind="unstyled"
          mailto="contact@alergeek.ventures"
          class="text-orange-700 hover:underline"
        >
          contact@alergeek.ventures
        </FirmowidWeb.DesignSystem.Components.Link.link>
      </p>
    </.legal_page>
    """
  end
end
