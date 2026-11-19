---
title: "Pobieranie faktur z KSeF w Firmowidzie: co, kiedy i z jakiego okresu"
description: "Firmowid sam pobiera z KSeF faktury kosztowe i sprzedażowe: 30 dni wstecz po połączeniu, potem co 2 godziny. Co trafia na listę, a co jest pomijane."
published: 2026-11-18
updated: 2026-11-18
category: faktury-i-ksef
---

Po połączeniu z KSeF Firmowid pobiera faktury sam. Zaraz po pierwszym połączeniu ściąga dokumenty z ostatnich 30 dni, a potem sprawdza KSeF co 2 godziny. Dotyczy to faktur kosztowych oraz faktur sprzedażowych, które wystawiłeś w innym programie.

## Co trzeba mieć

Aktywne połączenie z KSeF. Jak je ustawić, opisuje instrukcja [Jak połączyć Firmowid z KSeF](/pomoc/polaczenie-z-ksef). Łączy administrator, a pobrane faktury widzą role: fakturowanie, księgowość i admin.

## Co Firmowid pobiera

| Rodzaj | Które dokumenty | Gdzie je znajdziesz |
|---|---|---|
| Faktury kosztowe | wszystkie faktury zakupu, na których Twoja firma jest nabywcą | „Faktury”, filtr „Zakupowe” |
| Faktury sprzedażowe | faktury VAT i korekty wystawione poza Firmowidem | „Faktury”, filtr „Sprzedażowe” |

Faktur, które wystawiłeś w Firmowidzie, program nie pobiera drugi raz. Rozpoznaje je po numerze KSeF.

Pobrana faktura sprzedażowa jest od razu zablokowana do edycji, tak samo jak faktura potwierdzona przez KSeF. Zachowuje dane sprzedawcy, daty i stawki z oryginalnego dokumentu.

![Lista faktur z filtrem „Zakupowe”](/images/guides/pomoc/faktury-zakupowe.webp)

## Kiedy i z jakiego okresu

| Zdarzenie | Zakres pobierania |
|---|---|
| Pierwsze połączenie z KSeF | ostatnie 30 dni |
| Automat co 2 godziny | wszystko, co KSeF zapisał od ostatnio pobranej faktury; gdy nie ma jeszcze żadnej, ostatnie 60 dni |
| Przycisk „Pobierz faktury z KSeF” | to samo co automat |

Starszych faktur z interfejsu nie pobierzesz. Jeśli potrzebujesz dokumentu kosztowego sprzed tego okresu, wgraj go jako plik.

## Jak pobrać faktury od razu

Nie musisz czekać na kolejny pełny cykl.

1. Otwórz ustawienia firmy i przejdź do ekranu „Integracja z KSeF”.
2. Kliknij „Pobierz faktury z KSeF”.
3. Poczekaj, aż zniknie napis „Trwa pobieranie faktur”.

Jeśli pobieranie właśnie trwa, przycisk nie uruchomi drugiego. Przy większej liczbie dokumentów KSeF przygotowuje paczkę nawet kilkanaście minut, więc faktury mogą pojawiać się na liście z opóźnieniem.

## Których faktur sprzedażowych Firmowid nie pobierze

Przy sprzedaży program zapisuje tylko zwykłe faktury VAT i korekty, które potrafi wiernie pokazać. Pomija między innymi:

- faktury zaliczkowe, rozliczeniowe i uproszczone wystawione w innym programie,
- faktury z mechanizmem podzielonej płatności, samofakturowanie i procedurę marży,
- faktury z płatnością częściową, skontem albo faktoringiem,
- faktury z okresem sprzedaży zamiast jednej daty i pozycje podane tylko w kwotach brutto,
- korekty, które podają same różnice,
- dokumenty z numerem, który w Firmowidzie nosi już inna faktura.

Pominięta faktura pozostaje w KSeF bez zmian. Firmowid zapisuje ją jako brakującą i zgłasza błąd zespołowi Firmowida, ale kolejne pobieranie jej nie ponawia: zaczyna od faktur zapisanych w KSeF później. Pojawi się w programie dopiero wtedy, gdy zespół usunie przyczynę i pobierze ją jeszcze raz.

Faktur kosztowych to ograniczenie nie dotyczy. Na listę trafiają wszystkie.

## Ta sama faktura z KSeF i z pliku

Zdarza się, że dostawca wysyła PDF e-mailem, a faktura jest też w KSeF. Jeśli wgrasz taki plik, a Firmowid odczyta z niego numer KSeF dokumentu, który już pobrał, druga faktura nie powstanie. Zobaczysz komunikat „Duplikat faktury” z linkiem do istniejącej.

Plik bez numeru KSeF nie zostanie rozpoznany jako ten sam dokument. Dlatego faktury od dostawców, którzy wystawiają w KSeF, lepiej zostawić automatowi.

## Co się dzieje po rozłączeniu KSeF

Pobieranie zatrzymuje się, a faktury ściągnięte wcześniej zostają w programie. Po ponownym połączeniu Firmowid dociąga dokumenty zapisane w KSeF od ostatnio pobranej faktury.

## Czego Firmowid tu nie robi

Nie pobiera urzędowego poświadczenia odbioru (UPO) i nie eksportuje faktur do pliku XML. Dokumenty możesz pobrać jako PDF, także zbiorczo w paczce miesiąca dla biura księgowego.

## Powiązane

- [Faktury z wysyłką do KSeF](/ksef)
- [Paczka dokumentów dla biura księgowego](/pomoc/paczka-dla-biura-ksiegowego)
