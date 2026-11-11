defmodule Firmowid.Core.Services.CompanyRegister do
  @moduledoc """
  Looks companies up in the VAT white list and KRS, then sole proprietorships
  in CEIDG, falling back to GUS when configured. Answers are cached per NIP
  for all organizations and looked up again once stale. Missing NIPs are
  batched by 30 for MF; KRS, CEIDG and GUS calls are sequential.
  Registry failures are returned to the caller without caching them.
  """

  alias Firmowid.Core
  alias Firmowid.Core.Nip
  alias Firmowid.Core.RegisteredCompany
  alias Firmowid.Core.Services.VatApiClient
  alias Firmowid.Scope
  alias Gusex.Types.OsFizycznaPkd
  alias Gusex.Types.OsPrawnaPkd
  alias Gusex.Types.Podmiot

  # One lookup takes two GUS requests. GUS allows 3 per second, 120 per minute
  # and 6000 per hour, so lookups are at least 1.25 s apart (at most 96 requests
  # a minute, 5760 an hour); the classification queue runs one job at a time.
  @pause_ms 1_250

  # CEIDG allows 50 requests in 3 minutes and 1000 an hour, and blocks for 3 minutes
  # when exceeded; a steady 3.7 s between requests keeps under both.
  @ceidg_pause_ms 3_700

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
           {:ok, attrs} <- gus_fallback(attrs),
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
        with {:ok, activity} <- krs_activity(krs, "P") do
          {:ok, Map.merge(base, activity)}
        end
    end
  end

  defp krs_activity(krs, registry) do
    options =
      Keyword.merge(
        [
          url: "https://api-krs.ms.gov.pl/api/krs/OdpisAktualny/#{krs}",
          params: [rejestr: registry, format: "json"],
          retry: false
        ],
        Application.get_env(:firmowid, :krs_api_request_options, [])
      )

    case Req.get(options) do
      {:ok, %{status: 200, body: %{"odpis" => %{"dane" => data}}}} ->
        activities =
          get_in(data, ["dzial3", "przedmiotDzialalnosci", "przedmiotPrzewazajacejDzialalnosci"])

        {:ok, krs_predominant(activities)}

      {:ok, %{status: 404}} when registry == "P" ->
        krs_activity(krs, "S")

      {:ok, %{status: 404}} ->
        {:ok, %{}}

      {:ok, %{status: status}} ->
        {:error, {:krs_http_error, status}}

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
    case Application.get_env(:firmowid, :ceidg_api_token) do
      nil ->
        {:ok, attrs}

      token ->
        Process.sleep(@ceidg_pause_ms)
        ceidg_activity(attrs, token)
    end
  end

  defp ceidg_activity(attrs, token) do
    case Req.get("https://dane.biznes.gov.pl/api/ceidg/v3/firma",
           params: [nip: attrs.nip],
           auth: {:bearer, token},
           retry: false
         ) do
      {:ok, %{status: 200, body: %{"firma" => businesses}}} ->
        {:ok, ceidg_attrs(attrs, ceidg_current(businesses))}

      {:ok, %{status: 204}} ->
        {:ok, attrs}

      {:ok, %{status: status}} ->
        {:error, {:ceidg_http_error, status}}

      {:error, _reason} = error ->
        error
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

  defp gus_fallback(%{pkd: _pkd} = attrs), do: {:ok, attrs}

  defp gus_fallback(attrs) do
    if Application.get_env(:gusex, :api_key) do
      Process.sleep(@pause_ms)

      with {:ok, gus_attrs} <- lookup(attrs.nip) do
        {:ok, Map.merge(attrs, gus_attrs)}
      end
    else
      {:ok, attrs}
    end
  end

  # A NIP GUS does not know, or a business it no longer publishes activities of
  # (error 11, deregistered before 2014-11-08), is stored without activity, as
  # is one found only as a local unit.
  defp lookup(nip) do
    case Gusex.find_by_nip(nip) do
      {:ok, entities} ->
        case Enum.find(entities, &(&1."Typ" in ["P", "F"])) do
          %Podmiot{} = entity -> activity(nip, entity)
          nil -> {:ok, %{nip: nip}}
        end

      {:error, %{ErrorCode: "4"}} ->
        {:ok, %{nip: nip}}

      {:error, _reason} = error ->
        error
    end
  end

  defp activity(nip, %Podmiot{Typ: type, Regon: regon, Nazwa: name, SilosID: silo}) do
    base = %{nip: nip, regon: regon, name: name}

    case Gusex.SessionCache.run_with_session(&Gusex.dane_pobierz_pelny_raport(regon, report(type), &1)) do
      {:ok, report} -> {:ok, Map.merge(base, predominant(report, silo))}
      {:error, %{ErrorCode: "11"}} -> {:ok, base}
      {:error, _reason} = error -> error
    end
  end

  # Legal entities and natural persons keep their activities in different reports.
  defp report("P"), do: "BIR12OsPrawnaPkd"
  defp report("F"), do: "BIR12OsFizycznaPkd"

  defp predominant(report, silo) do
    case Enum.find(report, &predominant?(&1, silo)) do
      nil -> %{}
      activity -> %{pkd: format_code(code(activity)), pkd_name: name(activity)}
    end
  end

  defp predominant?(%OsPrawnaPkd{praw_pkdPrzewazajace: flag}, _silo), do: flag == "1"

  defp predominant?(%OsFizycznaPkd{fiz_pkdPrzewazajace: flag, fiz_SilosID: silo}, silo), do: flag == "1"

  defp predominant?(%OsFizycznaPkd{}, _silo), do: false

  defp code(%OsPrawnaPkd{praw_pkdKod: code}), do: code
  defp code(%OsFizycznaPkd{fiz_pkdKod: code}), do: code

  defp name(%OsPrawnaPkd{praw_pkdNazwa: name}), do: name
  defp name(%OsFizycznaPkd{fiz_pkdNazwa: name}), do: name

  # GUS and CEIDG give "6920Z"; the classification writes "69.20.Z".
  defp format_code(<<division::binary-size(2), group::binary-size(2), class::binary>>),
    do: "#{division}.#{group}.#{class}"
end
