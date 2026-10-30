defmodule Firmowid.Core.Services.CompanyRegister do
  @moduledoc """
  Looks companies up in the GUS register by NIP and caches the answers in
  `Firmowid.Core.RegisteredCompany`, so each NIP is asked for once for all
  organizations.

  GUS allows at most 3 requests per second, so missing NIPs are looked up one
  after another with a pause. Failures are returned to the caller.
  """

  alias Firmowid.Core
  alias Firmowid.Core.Nip
  alias Firmowid.Core.RegisteredCompany
  alias Firmowid.Scope
  alias Gusex.Types.OsFizycznaPkd
  alias Gusex.Types.OsPrawnaPkd
  alias Gusex.Types.Podmiot

  # One lookup takes two GUS requests. GUS allows 3 per second, 120 per minute
  # and 6000 per hour, so lookups are at least 1.25 s apart (at most 96 requests
  # a minute, 5760 an hour); the classification queue runs one job at a time.
  @pause_ms 1_250

  @doc """
  Returns the cached register data of the valid Polish `nips` by NIP, first
  looking up and storing those not cached yet when a GUS key is configured.
  """
  @spec fetch([String.t()], Scope.t()) ::
          {:ok, %{String.t() => RegisteredCompany.t()}} | {:error, term()}
  def fetch(nips, scope) do
    nips = nips |> Enum.filter(&Nip.valid?/1) |> Enum.map(&Nip.normalize_digits/1) |> Enum.uniq()
    cached = Core.list_registered_companies!(nips, scope: scope)
    # Without a GUS key, e.g. in production before one is configured, only cached data is used.
    missing =
      if Application.get_env(:gusex, :api_key), do: nips -- Enum.map(cached, & &1.nip), else: []

    # Pausing before every lookup also spaces out lookups of consecutive jobs.
    missing
    |> Enum.reduce_while({:ok, cached}, fn nip, {:ok, companies} ->
      Process.sleep(@pause_ms)

      with {:ok, attrs} <- lookup(nip),
           {:ok, company} <- Core.register_company(attrs, scope: scope) do
        {:cont, {:ok, [company | companies]}}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, companies} -> {:ok, Map.new(companies, &{&1.nip, &1})}
      {:error, _reason} = error -> error
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

  # GUS gives "6920Z"; the classification writes "69.20.Z".
  defp format_code(<<division::binary-size(2), group::binary-size(2), class::binary>>),
    do: "#{division}.#{group}.#{class}"
end
