---
title: "Jak przekazać faktury biuru księgowemu: paczka dokumentów za miesiąc"
description: "Jeden plik ZIP z fakturami sprzedażowymi i kosztowymi za wybrany miesiąc. Co zawiera, jak nazywają się pliki i co ustawić przed pobraniem."
published: 2026-11-18
updated: 2026-11-18
category: bank-i-platnosci
---

W Firmowidzie pobierasz wszystkie faktury z danego miesiąca jako jeden plik ZIP i wysyłasz go do biura rachunkowego. W środku są osobne katalogi na faktury sprzedażowe i kosztowe, a pliki mają nazwy z datą albo numerem i kontrahentem.

## Co trzeba mieć

- Rolę z dostępem do faktur: „fakturowanie”, „księgowość” albo administratora.
- Komputer. Na telefonie przycisk „Pobierz” nie jest dostępny.

## Kroki

1. Otwórz „Faktury” w pasku bocznym.
2. Przewiń listę do miesiąca, który chcesz przekazać. Paczka dotyczy miesiąca widocznego na ekranie.
3. Kliknij „Pobierz”. Otworzy się okno z wyborem zawartości.

![Okno „Pobierz faktury” z wyborem zawartości paczki](/images/guides/pomoc/paczka-okno.webp)

4. Zaznacz, co ma trafić do paczki:

| Opcja | Domyślnie | Co to jest |
|---|---|---|
| „Wgrane dokumenty cyfrowe (PDF)” | zaznaczone | faktury kosztowe wgrane jako PDF |
| „Faktury sprzedażowe” | zaznaczone | faktury, które wystawiłeś |
| „Kosztowe z KSeF (PDF generowane z danych KSeF)” | odznaczone | faktury kosztowe pobrane z KSeF, zapisane jako czytelny PDF |
| „Zdjęcia i skany dokumentów” | odznaczone | faktury kosztowe wgrane jako zdjęcie albo skan |

5. Zdecyduj o przełączniku „Dołącz komentarze wewnętrzne do generowanych PDF-ów”. Domyślnie jest włączony.
6. Kliknij „Pobierz dokumenty”. Przeglądarka zapisze plik ZIP.

## Co jest w paczce

Do paczki trafiają dokumenty, których data wystawienia albo data sprzedaży przypada w wybranym miesiącu.

| Katalog | Zawartość | Wzór nazwy pliku |
|---|---|---|
| `sprzedazowe/` | faktury sprzedażowe w PDF | numer faktury i nabywca |
| `kosztowe/` | faktury kosztowe: PDF, a zdjęcia i skany w oryginalnym formacie | data wystawienia, sprzedawca i krótki kod pliku |

Nazwy są zapisane małymi literami, bez polskich znaków, ze znakiem podkreślenia w miejscu spacji. Dzięki dacie na początku faktury kosztowe układają się w katalogu chronologicznie.

## Na co uważać przed wysłaniem

**Komentarze wewnętrzne.** Jeśli przy fakturach zapisujesz uwagi tylko dla siebie, wyłącz przełącznik komentarzy. Przy włączonym trafią one na generowane PDF-y i zobaczy je każdy, kto otworzy paczkę. Z drugiej strony to wygodny sposób, żeby przekazać biuru księgowemu opis wydatku, na przykład „laptop dla nowej osoby”.

**Faktury kosztowe z KSeF.** Ta opcja jest domyślnie odznaczona, bo biuro księgowe z uprawnieniami w KSeF pobiera je samo. Zaznacz ją, gdy biuro księgowe woli dostać komplet w jednym miejscu.

**Zdjęcia i skany.** Też są domyślnie odznaczone. Jeżeli paragony i faktury papierowe fotografujesz telefonem, włącz tę opcję, inaczej ich w paczce zabraknie.

**Faktura na przełomie miesięcy.** Dokument wystawiony 2 grudnia z datą sprzedaży 30 listopada znajdzie się w paczce listopadowej i w grudniowej. Uprzedź o tym biuro księgowe albo ustalcie, według której daty pracujecie.

## Czego Firmowid tu nie robi

- Paczka zawiera pliki PDF i obrazy. Nie ma w niej pliku JPK ani faktur w formacie XML.
- Nie ma w niej wyciągu bankowego ani listy przelewów.
- Faktura kosztowa, do której program nie ma jeszcze pliku, nie trafi do paczki. Zdarza się to przy fakturze z KSeF pobranej chwilę wcześniej. Pobierz paczkę ponownie po kilku minutach i porównaj liczbę plików z listą faktur.
- Firmowid nie wysyła paczki do biura. Plik przekazujesz samodzielnie, tak jak dotąd.

## Gdy biuro księgowe chce mieć dostęp na bieżąco

Zamiast paczki możesz zaprosić osobę z biura księgowego do firmy z rolą „księgowość”. Zobaczy wtedy faktury i przelewy od razu, bez czekania na koniec miesiąca.

## Powiązane

- [Bank i dopasowanie przelewów do faktur](/funkcje/bank)
- [Jak działa dopasowanie przelewów](/pomoc/dopasowanie-przelewow)
