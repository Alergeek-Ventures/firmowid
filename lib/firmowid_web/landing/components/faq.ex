defmodule FirmowidWeb.Landing.Components.Faq do
  @moduledoc """
  Localized accordion and FAQPage structured data.
  """

  use FirmowidWeb, :html

  alias Phoenix.LiveView.Rendered

  @doc """
  Renders the accordion and, when `structured_data?` is set, encodes the same
  answers as FAQPage JSON-LD.
  """
  @spec faq_section(map()) :: Rendered.t()
  attr :open_faq, :string, default: nil
  attr :structured_data?, :boolean, default: false
  attr :standalone?, :boolean, default: false

  # sobelow_skip ["XSS.Raw"]
  # JSON encoding and escaping '<' prevent translated answers from closing the script element.
  def faq_section(assigns) do
    faqs = localize(entries())
    schema = encode_schema(faqs)

    assigns = assign(assigns, faqs: faqs, schema: schema)

    ~H"""
    <section
      id="faq"
      class={[
        "bg-grey-50 py-18 lg:py-26 max-lg:[&>div>*]:min-w-0",
        !@standalone? && "border-t border-rust-200"
      ]}
    >
      <div class="mx-auto grid w-[calc(100%-var(--spacing)*8)] max-w-284.75 gap-8 lg:w-[calc(100%-var(--spacing)*16)] lg:grid-cols-[minmax(0,1fr)_571px] lg:gap-12 [&_article]:rounded-lg [&_article]:border-2 [&_article]:border-rust-200 [&_article]:bg-white [&_button]:flex [&_button]:w-full [&_button]:cursor-pointer [&_button]:items-center [&_button]:justify-between [&_button]:gap-6 [&_button]:p-5 [&_button]:text-left [&_button]:text-base [&_button]:leading-[1.4] [&_button]:font-semibold lg:[&_button]:text-h5/tight **:[[role='region']]:text-[15px] **:[[role='region']]:leading-[23px] **:[[role='region']]:text-grey-700">
        <div class="max-w-180 lg:max-w-284.75">
          <p
            :if={!@standalone?}
            class="mb-4 text-xs font-bold tracking-[0.08em] text-(--landing-accent) uppercase"
          >
            {gettext("Questions and answers")}
          </p>
          <.dynamic_tag
            tag_name={if @standalone?, do: "h1", else: "h2"}
            class="text-[38px] leading-[1.1] font-bold tracking-[-0.03em] text-balance max-lg:wrap-anywhere lg:text-[48px] lg:leading-[50px] lg:tracking-[-1px]"
          >
            {if @standalone?,
              do: gettext("Questions and answers"),
              else: gettext("Before you ask — we may have already answered.")}
          </.dynamic_tag>
          <p class="mt-6 text-h5/6.75 text-grey-700 lg:max-w-115">
            {gettext("Didn't find your question?")}
            <a
              href="mailto:contact@alergeek.ventures"
              class="font-bold text-grey-700 no-underline transition-colors duration-300 hover:text-rust-700 max-lg:block"
            >
              {gettext("Write to us.")}
            </a>
          </p>
        </div>

        <div class="grid content-start gap-2">
          <article :for={faq <- @faqs}>
            <button
              id={"faq-#{faq.id}"}
              type="button"
              phx-click="toggle_faq"
              phx-value-id={faq.id}
              aria-expanded={to_string(@open_faq == faq.id)}
              aria-controls={"faq-panel-#{faq.id}"}
              class="transition-[color,padding] duration-300 ease-in-out hover:text-rust-700 aria-expanded:pb-2.5 motion-reduce:transition-none"
            >
              <span>{faq.question}</span>
              <span
                class="flex-none text-xl leading-none text-(--landing-accent)"
                aria-hidden="true"
              >
                {if @open_faq == faq.id, do: "−", else: "+"}
              </span>
            </button>
            <div
              id={"faq-panel-#{faq.id}"}
              role="region"
              aria-labelledby={"faq-#{faq.id}"}
              aria-hidden={to_string(@open_faq != faq.id)}
              inert={@open_faq != faq.id}
              class={[
                "grid transition-[grid-template-rows,opacity] duration-300 ease-in-out motion-reduce:transition-none",
                if(@open_faq == faq.id,
                  do: "grid-rows-[1fr] opacity-100",
                  else: "grid-rows-[0fr] opacity-0"
                )
              ]}
            >
              <div class="min-h-0 overflow-hidden">
                <div class="px-5 pb-5">
                  <p :for={paragraph <- faq.answer} class="mt-[23px] first:mt-0">{paragraph}</p>
                </div>
              </div>
            </div>
          </article>
        </div>
      </div>

      <script :if={@structured_data?} type="application/ld+json">
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
        answer: [
          gettext_noop(
            "Yes. Firmowid sends sales invoices to KSeF and shows the KSeF number on the invoice. It downloads cost invoices from KSeF every 2 hours, including in the Free plan. It connects to KSeF with a Trusted Profile, a KSeF certificate or a token."
          )
        ]
      },
      %{
        id: "migracja",
        question: gettext_noop("How does migration from another program work?"),
        answer: [
          gettext_noop(
            "You start by connecting KSeF and your bank. Firmowid downloads the invoices from the last 30 days from KSeF and the transfers from the last 3 months from your bank on its own, so you can match transfers to invoices right away. You can add older cost invoices as a PDF or a photo. Several invoicing programs can be connected to KSeF at once, so your old program can keep working alongside Firmowid until you switch."
          )
        ]
      },
      %{
        id: "bezpieczenstwo",
        question: gettext_noop("Is my data safe?"),
        answer: [
          gettext_noop(
            "Your data is stored on OVH servers in the European Union. You connect your bank as read-only: Firmowid does not order transfers and does not see your bank password, because you log in on the bank's website."
          )
        ]
      },
      %{
        id: "anulowanie",
        question: gettext_noop("Can I cancel at any time?"),
        answer: [
          gettext_noop("Yes. You can cancel at any time and delete your account without long-term commitments.")
        ]
      },
      %{
        id: "banki",
        question: gettext_noop("Which banks do you support?"),
        answer: [
          gettext_noop(
            "Firmowid connects to your bank via Open Banking (partner: GoCardless). We support 29 banks and payment institutions:"
          ),
          gettext_noop(
            "Polish banks: PKO Bank Polski (iPKO and iPKO Biznes), Inteligo, Bank Pekao, mBank (retail and Corporate), ING, Erste Bank Polska (retail and Corporate), Alior Bank, Bank Millennium, BNP Paribas (retail and Corporate), Nest Bank (Private and Corporate)."
          ),
          gettext_noop(
            "Fintech and payments: Revolut, Wise, Stripe, PayPal, Paysera, N26, Airwallex, Finom, Vivid Money, Monese, Lunar, Swan, Soldo, Ebury, Skrill, Neteller."
          ),
          gettext_noop("Foreign banks: HSBCnet, Aion Bank, Ikano Bank."),
          gettext_noop(
            "Don't see your bank? Add an account manually by entering its IBAN. You can issue invoices with this account, just without automatically importing transfers."
          )
        ]
      },
      %{
        id: "oplaty",
        question: gettext_noop("Does Firmowid charge extra for invoices or KSeF?"),
        answer: [
          gettext_noop(
            "No. Invoices and KSeF are unlimited in every plan, including Free. Your plan sets the number of banks (1, 3 or unlimited) and users (2, 5 or unlimited)."
          )
        ]
      },
      %{
        id: "poza-ksef",
        question: gettext_noop("Can I add invoices from outside KSeF?"),
        answer: [
          gettext_noop(
            "Yes, in every plan, including Free. KSeF invoices arrive automatically, and you simply drag invoices from outside KSeF (e.g. foreign invoices) into Firmowid. We match them with transfers just like the rest."
          )
        ]
      },
      %{
        id: "ksiegowosc",
        question: gettext_noop("Do I need an invoicing program or accounting software?"),
        answer: [
          gettext_noop(
            "If an accounting office keeps your records and settles taxes, an invoicing program with KSeF is enough. You need accounting software when you handle those settlements yourself, and an ERP only when invoices come from orders, a warehouse or production. Firmowid does not keep the KPiR ledger, lump-sum tax, ZUS or tax returns, but it prepares a monthly ZIP package of documents for your accountant."
          )
        ]
      }
    ]
  end

  defp localize(entries) do
    Enum.map(entries, fn entry ->
      %{
        entry
        | question: Gettext.gettext(Firmowid.Gettext, entry.question),
          answer: Enum.map(entry.answer, &Gettext.gettext(Firmowid.Gettext, &1))
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
            "acceptedAnswer" => %{"@type" => "Answer", "text" => Enum.join(faq.answer, "\n\n")}
          }
        end)
    }
    |> Jason.encode!()
    |> String.replace("<", "\\u003c")
  end
end
