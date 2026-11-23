defmodule Firmowid.Core.Services.CompanyRegister do
  @moduledoc """
  Looks companies up in the VAT white list and KRS, then sole proprietorships
  in CEIDG. Answers are cached per NIP for all organizations and looked up
  again once stale. Missing NIPs are batched by 30 for MF; KRS and CEIDG calls
  are sequential.
  Registry failures are returned to the caller without caching them.
  """

  alias Firmowid.Core
  alias Firmowid.Core.Nip
  alias Firmowid.Core.RegisteredCompany
  alias Firmowid.Core.Services.CeidgApiClient
  alias Firmowid.Core.Services.KrsApiClient
  alias Firmowid.Core.Services.VatApiClient
  alias Firmowid.Scope

  @doc """
  Returns the cached register data of the valid Polish `nips` by NIP, first
  looking up and storing those not cached yet or stale: without an activity
  after 30 days, otherwise after a year.
  """
  @spec fetch([String.t()], Scope.t()) ::
          {:ok, %{String.t() => RegisteredCompany.t()}} | {:error, term()}
  def fetch(nips, scope) do
    nips = nips |> Enum.filter(&Nip.valid?/1) |> Enum.map(&Nip.normalize_digits/1) |> Enum.uniq()
    cached = nips |> Core.list_registered_companies!(scope: scope) |> Enum.reject(&stale?/1)
    missing = nips -- Enum.map(cached, & &1.nip)

    missing
    |> Enum.chunk_every(30)
    |> Enum.reduce_while({:ok, cached}, fn batch, {:ok, companies} ->
      with {:ok, subjects} <- VatApiClient.fetch_by_nips(batch),
           {:ok, stored} <- register_batch(batch, subjects, scope) do
        {:cont, {:ok, stored ++ companies}}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, companies} -> {:ok, Map.new(companies, &{&1.nip, &1})}
      {:error, _reason} = error -> error
    end
  end

  # Registers fill in late and companies change activity, so cached answers are looked up again.
  defp stale?(company) do
    max_days = if company.pkd, do: 365, else: 30
    DateTime.diff(DateTime.utc_now(), company.updated_at, :day) >= max_days
  end

  defp register_batch(nips, subjects, scope) do
    Enum.reduce_while(nips, {:ok, []}, fn nip, {:ok, companies} ->
      # A NIP may list several subjects; the one registered in KRS has an activity to read.
      matching = Enum.filter(subjects, &(&1["nip"] == nip))
      subject = Enum.find(matching, &(&1["krs"] not in [nil, ""])) || List.first(matching)

      with {:ok, attrs} <- vat_activity(nip, subject),
           {:ok, attrs} <- ceidg_fallback(attrs),
           # A refreshed entry drops an activity the registers no longer report.
           attrs = Map.merge(%{pkd: nil, pkd_name: nil}, attrs),
           {:ok, company} <- Core.register_company(attrs, scope: scope) do
        {:cont, {:ok, [company | companies]}}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp vat_activity(nip, nil), do: {:ok, %{nip: nip}}

  defp vat_activity(nip, subject) do
    base = %{nip: nip, regon: subject["regon"], name: subject["name"]}

    case subject["krs"] do
      krs when krs in [nil, ""] ->
        {:ok, base}

      krs ->
        with {:ok, activity} <- krs_activity(krs) do
          {:ok, Map.merge(base, activity)}
        end
    end
  end

  defp krs_activity(krs) do
    case KrsApiClient.fetch_current(krs) do
      {:ok, data} when is_map(data) ->
        activities =
          get_in(data, ["dzial3", "przedmiotDzialalnosci", "przedmiotPrzewazajacejDzialalnosci"])

        {:ok, krs_predominant(activities)}

      # A struck-off entry has no current activity to read.
      {:ok, _struck_off_or_not_found} ->
        {:ok, %{}}

      {:error, _reason} = error ->
        error
    end
  end

  defp krs_predominant([activity | _]) do
    %{
      pkd: "#{activity["kodDzial"]}.#{activity["kodKlasa"]}.#{activity["kodPodklasa"]}",
      pkd_name: activity["opis"]
    }
  end

  defp krs_predominant(activities) when activities in [nil, []], do: %{}

  # KRS has no sole proprietorships, and the VAT white list misses those not paying VAT.
  defp ceidg_fallback(%{pkd: _pkd} = attrs), do: {:ok, attrs}

  defp ceidg_fallback(attrs) do
    case CeidgApiClient.fetch_businesses(attrs.nip) do
      {:ok, []} -> {:ok, attrs}
      {:ok, businesses} -> {:ok, ceidg_attrs(attrs, ceidg_current(businesses))}
      {:error, :not_configured} -> {:ok, attrs}
      {:error, _reason} = error -> error
    end
  end

  # A NIP may hold several businesses over the years; the active one, else the latest started.
  defp ceidg_current(businesses) do
    Enum.find(businesses, &(&1["status"] == "AKTYWNY")) ||
      Enum.max_by(businesses, & &1["dataRozpoczecia"])
  end

  defp ceidg_attrs(attrs, business) do
    regon = get_in(business, ["wlasciciel", "regon"])

    attrs
    |> Map.update(:name, business["nazwa"], &(&1 || business["nazwa"]))
    |> Map.update(:regon, regon, &(&1 || regon))
    |> Map.merge(ceidg_main(business["pkdGlowny"]))
  end

  defp ceidg_main(%{"kod" => code, "nazwa" => name}), do: %{pkd: format_code(code), pkd_name: name}

  defp ceidg_main(nil), do: %{}

  # CEIDG gives "6920Z"; the classification writes "69.20.Z".
  defp format_code(<<division::binary-size(2), group::binary-size(2), class::binary>>),
    do: "#{division}.#{group}.#{class}"
end
