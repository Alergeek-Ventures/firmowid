defmodule FirmowidWeb.Landing.Components.Faq do
  @moduledoc """
  Localized accordion and FAQPage structured data.
  """

  use FirmowidWeb, :html

  alias Phoenix.LiveView.Rendered

  @doc """
  Renders the accordion and encodes the same answers as FAQPage JSON-LD.
  """
  @spec faq_section(map()) :: Rendered.t()
  attr :open_faq, :string, default: nil

  # sobelow_skip ["XSS.Raw"]
  # JSON encoding and escaping '<' prevent translated answers from closing the script element.
  def faq_section(assigns) do
    faqs = localize(entries())
    schema = encode_schema(faqs)

    assigns = assign(assigns, faqs: faqs, schema: schema)

    ~H"""
    <section id="faq" class="landing-section border-t border-orange-200 bg-grey-50">
      <div class="landing-container landing-faq">
        <div class="landing-section__intro">
          <p class="landing-eyebrow">{gettext("Questions and answers")}</p>
          <h2>{gettext("Before you ask — we may have already answered.")}</h2>
          <p>
            {gettext("Didn't find your question?")}
            <a href="mailto:contact@alergeek.ventures" class="font-bold text-darkGrey underline">
              {gettext("Write to us.")}
            </a>
          </p>
        </div>

        <div class="landing-faq__items">
          <article :for={faq <- @faqs}>
            <button
              id={"faq-#{faq.id}"}
              type="button"
              phx-click="toggle_faq"
              phx-value-id={faq.id}
              aria-expanded={to_string(@open_faq == faq.id)}
              aria-controls={"faq-panel-#{faq.id}"}
            >
              <span>{faq.question}</span>
              <span class="landing-faq__sign" aria-hidden="true">
                {if @open_faq == faq.id, do: "−", else: "+"}
              </span>
            </button>
            <div
              id={"faq-panel-#{faq.id}"}
              role="region"
              aria-labelledby={"faq-#{faq.id}"}
              hidden={@open_faq != faq.id}
            >
              {faq.answer}
            </div>
          </article>
        </div>
      </div>

      <script type="application/ld+json">
        <%= Phoenix.HTML.raw(@schema) %>
      </script>
    </section>
    """
  end

  defp entries do
    [
      %{
        id: "ksef",
        question: gettext_noop("Is Firmowid compliant with KSeF?"),
        answer:
          gettext_noop(
            "Yes. Full KSeF compliance and automatic tracking of regulatory changes — our developers implement them immediately after announcements from the Ministry of Finance."
          )
      },
      %{
        id: "migracja",
        question: gettext_noop("How does migration from another program work?"),
        answer:
          gettext_noop(
            "Start by connecting KSeF and your bank — we import data from the last three months. You can immediately match transactions to invoices and analyze cash flow."
          )
      },
      %{
        id: "bezpieczenstwo",
        question: gettext_noop("Is my data safe?"),
        answer:
          gettext_noop(
            "Yes. Firmowid emphasizes secure data storage, and the entire flow is designed for handling company financial data."
          )
      },
      %{
        id: "anulowanie",
        question: gettext_noop("Can I cancel at any time?"),
        answer: gettext_noop("Yes. You can cancel at any time and delete your account without long-term commitments.")
      },
      %{
        id: "banki",
        question: gettext_noop("Which banks do you support?"),
        answer:
          gettext_noop(
            "Firmowid connects to your bank via Open Banking (partner: GoCardless). We support 29 banks and payment institutions. Polish banks: PKO Bank Polski (iPKO and iPKO Biznes), Inteligo, Bank Pekao, mBank (retail and Corporate), ING, Erste Bank Polska (retail and Corporate), Alior Bank, Bank Millennium, BNP Paribas (retail and Corporate), Nest Bank (Private and Corporate). Fintech and payments: Revolut, Wise, Stripe, PayPal, Paysera, N26, Airwallex, Finom, Vivid Money, Monese, Lunar, Swan, Soldo, Ebury, Skrill, Neteller. No bank of yours? Add an account manually with its IBAN."
          )
      },
      %{
        id: "oplaty",
        question: gettext_noop("How do additional charges work?"),
        answer:
          gettext_noop(
            "There are no additional charges for invoices or KSeF - in every plan, including Free, they are unlimited. Only the number of bank accounts (1 / 3 / unlimited) and users (2 / 5 / unlimited) depends on your plan. Need more? Move to a higher plan, with no per-account charges."
          )
      },
      %{
        id: "poza-ksef",
        question: gettext_noop("Can I add invoices from outside KSeF?"),
        answer:
          gettext_noop(
            "Yes, in every plan, including Free. KSeF invoices arrive automatically, and you simply drag invoices from outside KSeF (e.g. foreign invoices) into Firmowid. We match them with transfers just like the rest."
          )
      }
    ]
  end

  defp localize(entries) do
    Enum.map(entries, fn entry ->
      %{
        entry
        | question: Gettext.gettext(Firmowid.Gettext, entry.question),
          answer: Gettext.gettext(Firmowid.Gettext, entry.answer)
      }
    end)
  end

  defp encode_schema(faqs) do
    %{
      "@context" => "https://schema.org",
      "@type" => "FAQPage",
      "mainEntity" =>
        Enum.map(faqs, fn faq ->
          %{
            "@type" => "Question",
            "name" => faq.question,
            "acceptedAnswer" => %{"@type" => "Answer", "text" => faq.answer}
          }
        end)
    }
    |> Jason.encode!()
    |> String.replace("<", "\\u003c")
  end
end
