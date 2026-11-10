defmodule Firmowid.Core.RegisteredCompany.Actions.LookUp do
  @moduledoc """
  Looks up the company a signed-in user is creating an organization for.

  The VAT white list gives the name, the working address and the VAT status; the
  cached public registers give the predominant activity (PKD), from which the
  industry is suggested. The activity is only a suggestion, so a register failure
  leaves it out instead of failing the lookup.
  """
  use Ash.Resource.Actions.Implementation

  alias Firmowid.Analysis.IndustryTemplate
  alias Firmowid.Core.Nip
  alias Firmowid.Core.Services.CompanyRegister
  alias Firmowid.Core.Services.VatApiClient
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  require Logger

  @impl true
  def run(input, _opts, _context) do
    nip = Nip.normalize_digits(input.arguments.nip)

    case VatApiClient.fetch_by_nip(nip) do
      {:ok, %{"result" => %{"subject" => nil}}} -> {:ok, nil}
      {:ok, %{"result" => %{"subject" => subject}}} -> {:ok, company(nip, subject)}
      {:error, _reason} = error -> error
    end
  end

  defp company(nip, subject) do
    activity = activity(nip)

    %{
      nip: nip,
      name: subject["name"],
      address: subject["workingAddress"] || subject["residenceAddress"],
      vat_payer?: subject["statusVat"] == "Czynny",
      pkd: activity[:pkd],
      pkd_name: activity[:pkd_name],
      industry: IndustryTemplate.industry_for_pkd(activity[:pkd])
    }
  end

  defp activity(nip) do
    scope = %Scope{actor: %SystemActor{org_id: nil, role: :company_lookup}, tenant: nil}

    case CompanyRegister.fetch([nip], scope) do
      {:ok, %{^nip => company}} ->
        %{pkd: company.pkd, pkd_name: company.pkd_name}

      {:ok, _companies} ->
        %{}

      {:error, reason} ->
        Logger.warning("Company register lookup failed",
          error_kind: Firmowid.ErrorKind.classify(reason)
        )

        %{}
    end
  end
end
