defmodule Firmowid.Billing.SubscriptionEmails do
  @moduledoc """
  Emails to an organization's admins about the card payments of its subscription: a declined
  charge that is tried again, with a link to change the card, and the last declined charge,
  after which the organization is back on Free (see `Firmowid.Billing.Payment`).

  Same frame and sender as `Firmowid.Billing.PlanLimitEmails`; the admins are read as that
  module's plan limits actor. The only amount named is the plan's price.
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: FirmowidWeb.Core.Endpoint,
    router: FirmowidWeb.Core.Router

  import Firmowid.Mailer.Components
  import Swoosh.Email

  alias Firmowid.Billing.Payment
  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Billing.PlanLimits
  alias Firmowid.Core
  alias Firmowid.Mailer
  alias FirmowidWeb.Billing.Utilities.Navigation
  alias FirmowidWeb.Core.Endpoint

  @doc """
  Tells the admins that a charge was declined, when it is tried again and that they can change
  the card before then.
  """
  @spec payment_declined(Payment.t()) :: {:ok, Swoosh.Email.t()} | {:error, term()}
  def payment_declined(payment) do
    assigns =
      payment
      |> base_assigns()
      |> Map.merge(%{
        next_attempt_on: format_date(payment.next_attempt_on),
        url: Endpoint.url() <> Navigation.card_change_path()
      })

    deliver(payment, "#{assigns.company}: płatność za plan #{assigns.plan} nie przeszła", %{
      html: declined_html(assigns),
      text: declined_text(assigns)
    })
  end

  @doc """
  Tells the admins that the last charge was declined, so the organization is back on the Free
  plan; what it uses above Free follows the plan limits.
  """
  @spec payment_failed(Payment.t()) :: {:ok, Swoosh.Email.t()} | {:error, term()}
  def payment_failed(payment) do
    assigns = Map.put(base_assigns(payment), :url, url(~p"/ustawienia/abonament"))

    deliver(payment, "#{assigns.company} wraca do planu #{PlanCatalog.name(:free)}", %{
      html: failed_html(assigns),
      text: failed_text(assigns)
    })
  end

  defp base_assigns(payment) do
    organization =
      Core.get_organization!(payment.organization_id,
        scope: PlanLimits.scope(payment.organization_id)
      )

    %{
      company: organization.display_name,
      plan: PlanCatalog.name(payment.plan),
      plan_row: "#{PlanCatalog.name(payment.plan)}, #{period_name(payment.billing_period)}",
      amount: Money.to_string!(Money.new(:PLN, payment.gross_amount), locale: "pl")
    }
  end

  defp deliver(payment, subject, %{html: html, text: text}) do
    scope = PlanLimits.scope(payment.organization_id)
    admins = Core.list_users!(%{status: :active, role: :admin}, scope: scope)

    email =
      new()
      |> to(Enum.map(admins, &to_string(&1.email)))
      |> from({"Firmowid", "piotr@firmowid.pl"})
      |> subject(subject)
      |> html_body(html)
      |> text_body(text)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp declined_html(assigns) do
    to_html(~H"""
    <.email preheader={"Spróbujemy ponownie #{@next_attempt_on}. Do tego czasu wszystko działa."}>
      <:headline>Płatność za plan {@plan} nie przeszła</:headline>
      <:lead>Spróbujemy ponownie {@next_attempt_on}. Do tego czasu wszystko działa normalnie.</:lead>
      <.detail_row label="Plan" value={@plan_row} />
      <.detail_row label="Kwota" value={"#{@amount} brutto"} />
      <.detail_row label="Następna próba" value={@next_attempt_on} />
      <div style="height:24px; line-height:24px; font-size:0;">&nbsp;</div>
      <.paragraph>
        Jeśli karta wygasła albo zabrakło na niej środków, zmień ją przed następną próbą.
        Nowa karta posłuży do kolejnych płatności.
      </.paragraph>
      <.paragraph>
        Jeśli ostatnia próba się nie uda, firma wróci do planu Darmowy.
      </.paragraph>
      <.button href={@url}>Zmień kartę</.button>
      <:footer>
        <.fallback_link href={@url} />
      </:footer>
    </.email>
    """)
  end

  defp declined_text(assigns) do
    """
    Płatność za plan #{assigns.plan} nie przeszła.

    Plan: #{assigns.plan_row}
    Kwota: #{assigns.amount} brutto
    Następna próba: #{assigns.next_attempt_on}

    Do tego czasu wszystko działa normalnie. Jeśli karta wygasła albo zabrakło na niej środków, zmień ją przed następną próbą. Nowa karta posłuży do kolejnych płatności.

    Jeśli ostatnia próba się nie uda, firma wróci do planu Darmowy.

    Zmień kartę: #{assigns.url}
    """
  end

  defp failed_html(assigns) do
    to_html(~H"""
    <.email preheader="Niczego nie usunęliśmy. Wyższy plan możesz kupić ponownie.">
      <:headline>Nie udało się pobrać płatności za plan {@plan}</:headline>
      <:lead>Firma wróciła do planu Darmowy.</:lead>
      <.detail_row label="Plan" value={@plan_row} />
      <.detail_row label="Kwota" value={"#{@amount} brutto"} />
      <div style="height:24px; line-height:24px; font-size:0;">&nbsp;</div>
      <.paragraph>
        Niczego nie usunęliśmy. Jeśli firma korzysta z więcej, niż obejmuje plan Darmowy,
        osobno napiszemy, co dalej. Wyższy plan możesz kupić ponownie, także z inną kartą.
      </.paragraph>
      <.button href={@url}>Zobacz abonament</.button>
      <:footer>
        <.fallback_link href={@url} />
      </:footer>
    </.email>
    """)
  end

  defp failed_text(assigns) do
    """
    Nie udało się pobrać płatności za plan #{assigns.plan}. Firma wróciła do planu Darmowy.

    Plan: #{assigns.plan_row}
    Kwota: #{assigns.amount} brutto

    Niczego nie usunęliśmy. Jeśli firma korzysta z więcej, niż obejmuje plan Darmowy, osobno napiszemy, co dalej. Wyższy plan możesz kupić ponownie, także z inną kartą.

    #{assigns.url}
    """
  end

  defp period_name(:monthly), do: "miesięcznie"
  defp period_name(:yearly), do: "rocznie"

  defp format_date(date), do: Firmowid.Cldr.Date.to_string!(date, format: :long, locale: "pl")
end
