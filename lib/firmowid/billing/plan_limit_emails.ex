defmodule Firmowid.Billing.PlanLimitEmails do
  @moduledoc """
  Emails to an organization's admins about usage above its billing plan: when it
  goes above the plan and when the plan switches the excess off (see
  `Firmowid.Billing.PlanLimits`).
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: FirmowidWeb.Core.Endpoint,
    router: FirmowidWeb.Core.Router

  import Firmowid.Mailer.Components
  import Swoosh.Email

  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Billing.PlanLimits
  alias Firmowid.Core.Organization
  alias Firmowid.Core.User
  alias Firmowid.LocalDate
  alias Firmowid.Mailer

  @doc """
  Tells the admins that the organization uses more than its plan includes and
  what happens from the decision day.
  """
  @spec deliver_limit_exceeded(
          [User.t()],
          Organization.t(),
          PlanCatalog.usage(),
          [PlanCatalog.limited()],
          Date.t()
        ) :: {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_limit_exceeded(admins, organization, usage, exceeded, decision_on) do
    limits = PlanCatalog.plan!(organization.billing_plan).limits

    assigns = %{
      company: organization.display_name,
      plan: plan_name(organization.billing_plan),
      rows: Enum.map(exceeded, &{label(&1), "#{usage[&1]}, plan obejmuje #{limits[&1]}"}),
      decision_today?: Date.compare(decision_on, LocalDate.today()) != :gt,
      decision_on: format_date(decision_on),
      switch_off_on: format_date(Date.add(decision_on, PlanLimits.decision_days())),
      url: url(~p"/limit-planu")
    }

    deliver(admins, "#{assigns.company} korzysta z więcej, niż obejmuje plan #{assigns.plan}", %{
      html: limit_exceeded_html(assigns),
      text: limit_exceeded_text(assigns)
    })
  end

  @doc """
  Tells the admins how many people, banks and projects the plan switched off
  and that a higher plan brings them back.
  """
  @spec deliver_excess_switched_off([User.t()], Organization.t(), %{
          PlanCatalog.limited() => non_neg_integer()
        }) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_excess_switched_off(admins, organization, switched_off) do
    assigns = %{
      company: organization.display_name,
      plan: plan_name(organization.billing_plan),
      rows:
        for(
          limited <- PlanCatalog.limited(),
          switched_off[limited] > 0,
          do: {label(limited), "#{switched_off[limited]}"}
        ),
      url: url(~p"/ustawienia/abonament")
    }

    deliver(
      admins,
      "#{assigns.company}: wyłączyliśmy to, co wykracza poza plan #{assigns.plan}",
      %{
        html: switched_off_html(assigns),
        text: switched_off_text(assigns)
      }
    )
  end

  defp deliver(admins, subject, %{html: html, text: text}) do
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

  defp limit_exceeded_html(assigns) do
    to_html(~H"""
    <.email preheader={"Wszystko działa normalnie. Decyzja od #{@decision_on}."}>
      <:headline>Twoja firma korzysta z więcej, niż obejmuje plan {@plan}</:headline>
      <:lead :if={!@decision_today?}>Wszystko działa normalnie do {@decision_on}.</:lead>
      <:lead :if={@decision_today?}>Wszystko działa, ale potrzebujemy Twojej decyzji.</:lead>
      <.detail_row :for={{label, value} <- @rows} label={label} value={value} />
      <div style="height:24px; line-height:24px; font-size:0;">&nbsp;</div>
      <.paragraph :if={!@decision_today?}>
        Od {@decision_on} wybierzesz: wyższy plan albo to, co zostaje włączone w planie {@plan}.
      </.paragraph>
      <.paragraph :if={@decision_today?}>
        Wybierz wyższy plan albo to, co zostaje włączone w planie {@plan}.
      </.paragraph>
      <.paragraph>
        Jeśli nie wybierzesz, {@switch_off_on} wyłączymy najnowsze osoby, banki i projekty ponad limit.
        Niczego nie usuwamy, a wyższy plan od razu je przywróci.
      </.paragraph>
      <.button href={@url}>{if @decision_today?, do: "Wybierz teraz", else: "Zobacz możliwości"}</.button>
      <:footer>
        <.fallback_link href={@url} />
      </:footer>
    </.email>
    """)
  end

  defp limit_exceeded_text(assigns) do
    """
    Twoja firma korzysta z więcej, niż obejmuje plan #{assigns.plan}.

    #{Enum.map_join(assigns.rows, "\n", fn {label, value} -> "#{label}: #{value}" end)}

    #{if assigns.decision_today?, do: "Wybierz wyższy plan albo to, co zostaje włączone w planie #{assigns.plan}.", else: "Wszystko działa normalnie do #{assigns.decision_on}. Od tego dnia wybierzesz: wyższy plan albo to, co zostaje włączone w planie #{assigns.plan}."}

    Jeśli nie wybierzesz, #{assigns.switch_off_on} wyłączymy najnowsze osoby, banki i projekty ponad limit. Niczego nie usuwamy, a wyższy plan od razu je przywróci.

    #{assigns.url}
    """
  end

  defp switched_off_html(assigns) do
    to_html(~H"""
    <.email preheader="Niczego nie usunęliśmy. Wyższy plan wszystko przywróci.">
      <:headline>Wyłączyliśmy to, co wykracza poza plan {@plan}</:headline>
      <:lead>Nie było decyzji, więc zostały najstarsze osoby, banki i projekty.</:lead>
      <.detail_row :for={{label, value} <- @rows} label={label} value={value} />
      <div style="height:24px; line-height:24px; font-size:0;">&nbsp;</div>
      <.paragraph>
        Niczego nie usunęliśmy. Osoby i projekty są w archiwum, a konta w wyłączonych bankach zachowały historię, tylko się nie synchronizują.
        Wyższy plan od razu je przywróci.
      </.paragraph>
      <.button href={@url}>Zobacz abonament</.button>
      <:footer>
        <.fallback_link href={@url} />
      </:footer>
    </.email>
    """)
  end

  defp switched_off_text(assigns) do
    """
    Wyłączyliśmy to, co wykracza poza plan #{assigns.plan}.

    #{Enum.map_join(assigns.rows, "\n", fn {label, value} -> "#{label}: #{value}" end)}

    Niczego nie usunęliśmy. Osoby i projekty są w archiwum, a konta w wyłączonych bankach zachowały historię, tylko się nie synchronizują. Wyższy plan od razu je przywróci.

    #{assigns.url}
    """
  end

  defp label(:users), do: "Osoby"
  defp label(:bank_institutions), do: "Banki"
  defp label(:active_projects), do: "Projekty"

  defp plan_name(:free), do: "Darmowy"
  defp plan_name(:przedsiebiorca), do: "Przedsiębiorca"
  defp plan_name(:firma), do: "Firma"

  defp format_date(date), do: Firmowid.Cldr.Date.to_string!(date, format: :long, locale: "pl")
end
