defmodule FirmowidWeb.Invoicing.Utilities.BankBadgesTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias FirmowidWeb.Invoicing.Utilities.BankBadges

  test "resolves connected Revolut account maps by ID with name fallback" do
    assert BankBadges.badge_for(%{
             institution_id: "REVOLUT_REVOGB21",
             institution_name: "Revolut"
           }) == "Revolut"

    assert BankBadges.badge_for_institution(%{
             id: "REVOLUT_REVOGB21",
             name: "Revolut"
           }) == "Revolut"
  end

  test "resolves Revolut IDs and longer institution names" do
    assert BankBadges.badge_for("REVOLUT_REVOGB21") == "Revolut"
    assert BankBadges.badge_for_institution("REVOLUT_REVOGB21") == "Revolut"
    assert BankBadges.badge_for("Revolut Bank UAB") == "Revolut"
    assert BankBadges.badge_for_institution("Revolut Bank UAB") == "Revolut"
  end

  test "keeps mapped ID precedence over a conflicting name" do
    account = %{
      institution_id: "MBANK_CORPORATE_BREXPLPW",
      institution_name: "Revolut"
    }

    assert BankBadges.badge_for(account) == "mBank (firma)"
    assert BankBadges.badge_for_institution(account) == "mBank (firma)"
  end
end
