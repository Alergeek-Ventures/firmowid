defmodule Firmowid.Invoicing.Services.CounterpartyProposalCleanup do
  @moduledoc """
  Tidies the data proposed for a new counterparty with a small model: a short
  capitalized display name, a properly written legal name or person's name, and
  a one-line address without doubled separators.

  Companies may be looked up on the web to find the brand they are known by;
  private persons never are. Returns nil when the model fails, so the caller
  keeps the unprocessed proposal.
  """

  alias Firmowid.ErrorKind
  alias OpenaiEx.Responses

  require Logger

  @web_search_tool %{
    type: "web_search",
    search_context_size: "low",
    user_location: %{type: "approximate", country: "PL"}
  }

  @fields ~w(display_name full_name given_name surname address)

  @response_format %{
    type: "json_schema",
    name: "counterparty",
    strict: true,
    schema: %{
      type: "object",
      properties: Map.new(@fields, &{&1, %{type: "string"}}),
      required: @fields,
      additionalProperties: false
    }
  }

  @type input :: %{
          type: :company | :individual,
          full_name: String.t() | nil,
          given_name: String.t() | nil,
          surname: String.t() | nil,
          tax_id: String.t() | nil,
          country: String.t() | nil,
          address: String.t() | nil,
          registry_name: String.t() | nil,
          registry_address: String.t() | nil
        }

  @type result :: %{
          display_name: String.t() | nil,
          full_name: String.t() | nil,
          given_name: String.t() | nil,
          surname: String.t() | nil,
          address: String.t() | nil
        }

  @doc "Returns the cleaned-up fields of one buyer, or nil when the model fails."
  @spec clean(input()) :: result() | nil
  def clean(input) do
    request = %{
      model: "gpt-6-luna",
      reasoning: %{effort: "none"},
      # Web search calls count towards this limit.
      max_output_tokens: 1000,
      instructions: instructions(),
      input: prompt(input),
      text: %{format: @response_format}
    }

    request =
      if input.type == :company,
        do: Map.merge(request, %{tools: [@web_search_tool], tool_choice: "required"}),
        else: request

    client()
    |> Responses.create!(request)
    |> Map.fetch!("output")
    |> Enum.filter(&(&1["type"] == "message"))
    |> Enum.flat_map(& &1["content"])
    |> Enum.map_join(&(&1["text"] || ""))
    |> Jason.decode!()
    |> Map.new(fn {field, value} -> {String.to_existing_atom(field), blank_to_nil(value)} end)
  rescue
    error ->
      Logger.warning("Failed to clean up a counterparty proposal",
        error_kind: ErrorKind.classify(error)
      )

      nil
  end

  defp client do
    openai =
      :firmowid
      |> Application.get_env(:openai_api_key)
      |> OpenaiEx.new()
      |> OpenaiEx.with_receive_timeout(60_000)

    case Application.get_env(:firmowid, :openai_ex, [])[:base_url] do
      base_url when is_binary(base_url) and base_url != "" ->
        OpenaiEx.with_base_url(openai, base_url)

      _ ->
        openai
    end
  end

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp prompt(input) do
    [
      {"typ", if(input.type == :company, do: "firma", else: "osoba fizyczna")},
      {"nazwa na fakturze", input.full_name},
      {"imię", input.given_name},
      {"nazwisko", input.surname},
      {"NIP / tax id", input.tax_id},
      {"kraj", input.country},
      {"adres na fakturze", input.address},
      {"nazwa w Białej liście VAT", input.registry_name},
      {"adres w Białej liście VAT", input.registry_address}
    ]
    |> Enum.map_join("\n", fn {label, value} -> "- #{label}: #{value || "brak"}" end)
    |> then(&("Nabywca z faktur sprzedażowych:\n" <> &1))
  end

  defp instructions do
    String.trim("""
    Jesteś asystentem księgowym. Porządkujesz dane kontrahenta (klienta), które użytkownik
    tylko zatwierdzi, więc mają być od razu czyste i czytelne. Nie wymyślaj danych.

    Zwracasz (pusty tekst, gdy pole nie dotyczy albo brak danych):
    - display_name: krótka nazwa, pod którą klient jest znany. Marka zamiast nazwy prawnej,
      bez formy prawnej, bez kraju, bez opisu działalności. Słowa wielką literą, resztę małymi,
      nawet gdy dane są wersalikami; akronimy wielkimi (np. "PGE", "10 BPS"). Dla osoby
      fizycznej: imię i nazwisko. Przykłady: "KOLOMOLO SPÓŁKA Z OGRANICZONĄ
      ODPOWIEDZIALNOŚCIĄ" -> "Kolomolo"; "Apple Polska Sp. z o.o." -> "Apple";
      "VIKINGCO POLAND SP. Z O.O." -> "VikingCo"; "Answergrid, Inc d/b/a Kenley" -> "Kenley".
    - full_name: pełna nazwa prawna firmy z formą prawną, z poprawioną wielkością liter
      i skróconą formą prawną ("Kolomolo sp. z o.o.", "One Logistics sp. z o.o. sp.k.",
      "10 BPS, Inc."). Dla osoby fizycznej pusty tekst.
    - given_name, surname: tylko dla osoby fizycznej, wielką literą ("Jan", "Kowalski").
    - address: jedna linia "ulica numer, kod miasto", dla zagranicy na końcu ", kraj" po polsku.
      Usuń podwójne przecinki i spacje, popraw wielkość liter ("GRZEGÓRZECKA 8/2, 31-530 KRAKÓW"
      -> "Grzegórzecka 8/2, 31-530 Kraków"), dodaj "ul." tylko gdy było w danych. Gdy adres
      z faktury jest niepełny, a z Białej listy pełny dla tej samej firmy, użyj pełnego.
      Nie zgaduj brakującego miasta ani kodu.

    Jeśli masz wyszukiwarkę, użyj jej tylko do ustalenia marki firmy (zgodny NIP albo adres),
    nigdy do szukania osób prywatnych.
    """)
  end
end
