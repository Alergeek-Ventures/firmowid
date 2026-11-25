defmodule FirmowidWeb.Settings.Components.TaxSectionTest do
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Core
  alias Firmowid.Taxes

  test "keeps a partner who left the team selected", %{conn: conn} do
    admin = admin_fixture()
    org_id = admin.member.organization_id
    scope = %Firmowid.Scope{actor: admin, tenant: org_id}
    former = user_in_org_fixture(org_id)

    org_id
    |> Core.get_organization!(scope: scope)
    |> Core.update_organization!(%{legal_form: :civil_partnership, is_vat_payer: false},
      scope: scope
    )

    partner = fn member_id ->
      %{
        member_id: member_id,
        profit_share: 50,
        income_tax: :flat_tax,
        pit_advances: :monthly,
        social_insurance: :full,
        voluntary_sickness: false
      }
    end

    Taxes.create_tax_year!(
      %{
        year: Firmowid.LocalDate.today().year,
        partners: [partner.(admin.member.id), partner.(former.member.id)]
      },
      scope: scope
    )

    Core.archive_member!(former.member, scope: scope)

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/ustawienia/firma")

    # Without its option the select would show, and save, another person.
    assert view |> element("#tax_year_partners_1_member_id option[selected]") |> render() =~
             former.member.id
  end
end
