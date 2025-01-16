defmodule Firmowid.Documents.OpenAIEnrichment do
  def generate_description(document) do
    {:ok, response} =
      OpenAI.chat_completion(
        model: "gpt-4o-mini",
        max_completion_tokens: 80,
        messages: [
          %{
            role: "system",
            content:
              "Jesteś asystentem dla osób zajmujących się dokumentami " <>
                "i transakcjami w przedsiębiorstwie. Pomagasz w opisywaniu " <>
                "katalogowaniu i dopasowaniu ich do siebie."
          },
          %{
            role: "user",
            content: "
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
              " |> String.trim()
          }
        ]
      )

    description =
      response.choices
      |> List.first()
      |> Map.get("message")
      |> Map.get("content")

    description
  end
end
