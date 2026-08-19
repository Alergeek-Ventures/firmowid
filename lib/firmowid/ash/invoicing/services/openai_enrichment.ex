defmodule Firmowid.Ash.Invoicing.Services.OpenAIEnrichment do
  @moduledoc """
  Generates short descriptions for cost invoices using OpenAI,
  based on seller name and line items.
  """

  @spec generate_description(map()) :: String.t()
  def generate_description(document) do
    model = ReqLLM.model!(%{provider: :openai, id: "gpt-5-nano"})

    messages = [
      ReqLLM.Context.system(
        "Jesteś asystentem dla osób zajmujących się dokumentami " <>
          "i transakcjami w przedsiębiorstwie. Pomagasz w opisywaniu " <>
          "katalogowaniu i dopasowaniu ich do siebie."
      ),
      ReqLLM.Context.user(user_prompt(document))
    ]

    {:ok, provider_module} = ReqLLM.provider(model.provider)

    {:ok, request} =
      provider_module.prepare_request(
        :chat,
        model,
        messages,
        openai_options()
      )

    request
    |> Req.request!(request_options())
    |> Map.fetch!(:body)
    |> ReqLLM.Response.text()
  end

  defp request_options do
    :firmowid
    |> Application.get_env(:openai_enrichment, [])
    |> Keyword.get(:request_options, [])
  end

  defp openai_base_url do
    :firmowid
    |> Application.get_env(:openai_enrichment, [])
    |> Keyword.get(:base_url)
  end

  defp openai_options do
    maybe_put_base_url(
      api_key: Application.get_env(:firmowid, :openai_api_key),
      max_completion_tokens: 1200,
      reasoning_effort: :low
    )
  end

  defp maybe_put_base_url(options) do
    case openai_base_url() do
      base_url when is_binary(base_url) and base_url != "" ->
        Keyword.put(options, :base_url, base_url)

      _ ->
        options
    end
  end

  defp user_prompt(document) do
    String.trim("""
    Oto metadane faktury sprzedażowej, którą chcą skatalogować:
    {
      sprzedawca: #{document["seller"]},
      przedmioty na fakturze: #{inspect(document["items_list"])}
    }
    Na podstawie tych danych, przygotuj opis faktury (w języku polskim)
    Będzie on wykorzystywany przez osoby, które potencjalnie nie mają
    informacji o tym, czym zajmuje się firma sprzedawcy, lub czym jest
    dany artykuł wypisany w dokumencie.  Nie używaj słów 'faktura za'
    (bo każdy dokument to faktura) oraz nie zawieraj w opisie
    informacji, które są już dostępne w metadanych. Skup się na tym,
    co zostało zakupione.
    Dobre przykłady opisów:
    - Paliwo do samochodu z nr rej. RZ941AY, zakupione w Krakowie na stacji Orlen.
    - Abonament telekomunikacyjny, trzy numery telefonu oraz internet mobilny
    - Komunikator, opłata za jedno miejsce na planie pro start
    - Abonament na hosting email, plan Zoho Marketplace Mail Lite
    Postaraj się zamknąć w 5-10 słowach.
    """)
  end
end
