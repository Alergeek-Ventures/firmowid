---
title: "Program do faktur z dopasowaniem przelewów: import to nie Open Banking"
description: "Import MT940 to nie Open Banking. Porównanie programów, które łączą przelewy z fakturami, i limitów ich darmowych planów."
published: 2026-11-06
updated: 2026-11-11
category: bank-i-platnosci
---

O tym, od kiedy KSeF obowiązuje poszczególne firmy, pisaliśmy już [w poradniku o terminach](/poradnik/co-to-jest-ksef-i-e-faktura), dlatego tu tylko krótko przypomnimy najważniejsze. Faktury kosztowe odbiera się przez system od 1 lutego 2026 r., a większość przedsiębiorców wystawia w nim faktury od 1 kwietnia. Nadanie numeru KSeF potwierdza przyjęcie dokumentu przez system, lecz nie oznacza, że nabywca zapłacił należność. Informacja o wpłacie nadal znajduje się w banku i stamtąd trzeba ją dostarczyć do programu do faktur.

## Skąd program bierze informacje o wpłacie

Można to zrobić wyciągiem MT940, CSV lub XML, wgrywanym ręcznie po pobraniu z bankowości elektronicznej, albo przez Open Banking, gdzie historię rachunku pobiera uprawniony dostawca po zgodzie właściciela konta. Przy rozliczaniu bierze się pod uwagę kwotę wpłaty, numer rachunku nadawcy oraz treść wpisaną w tytule przelewu.

![Dwie drogi informacji o wpłacie do programu do faktur. Import pliku: eksport wyciągu MT940, CSV lub XML i ręczne wgranie. Open Banking: zgoda właściciela konta i pobranie historii przez AISP wpisanego do rejestru KNF. Przy rozliczaniu liczy się kwota wpłaty, numer rachunku nadawcy i tytuł przelewu.](/images/guides/skad-program-wie-o-wplacie-import-open-banking.webp)
*Numer KSeF potwierdza przyjęcie faktury, nie zapłatę. Informacja o wpłacie jest w banku.*

## Porównanie programów

![Osiem programów do faktur w kolejności alfabetycznej, z podziałem na połączenie z bankiem i import pliku. Open Banking przez GoCardless mają Firmowid (29 banków i fintechów) i Mobilna Faktura (2300+ banków UE). Afaktury i Fakturoza importują MT940 (Fakturoza w planie Darmowym 1 wyciąg miesięcznie), a wFirma CSV, MT940 i XML.](/images/guides/jak-transakcje-trafiaja-do-programu-do-faktur.webp)
*Źródła: strony producentów, dostęp 22.10–5.11.2026.*

| Program | Jak wchodzą transakcje | Jak łączy z fakturą | Tani albo darmowy próg | Główne ograniczenie |
|---|---|---|---|---|
| Firmowid | Open Banking (GoCardless); strona podaje 29 banków i fintechów | automatyczne parowanie przelewów | Darmowy: 1 konto bankowe, faktury i KSeF bez limitu | brak księgowości i magazynu |
| wFirma | integracja z bankiem oraz import CSV, MT940 i XML | automatyczne parowanie i sugestie, ręcznie albo nocą | stały plan 0 zł niepotwierdzony; test 30 dni | odbiór KSeF dopiero w pakiecie księgowym; cena dynamiczna |
| Fakturownia | Kontomatik albo import pliku | automatyczne łączenie płatności z fakturami | Micro: 3 faktury sprzedażowe / mies. | powyżej 3 faktur plan płatny |
| Mobilna Faktura | Open Banking PSD2 przez GoCardless, 2300+ banków UE; także CSV/MT940 | automatyczne dopasowanie transakcji do faktur | Free: 3 faktury / mies., bez połączenia z bankiem | oficjalny cennik opisuje znacznie szerszy system niż samo fakturowanie |
| Afaktury | import MT940 | automatyczne przypisanie wpłat i aktualizacja statusów | Free: 3 dokumenty i 10 PDF / mies. | Open Banking niepotwierdzony |
| ING Księgowość | historia transakcji z kont ING | podpowiada pasujące przelewy; łączenie bywa ręczne | fakturowanie 0 zł dla klientów ING | poza ING cena i limit niepodane |
| SaldeoSMART | automatyczne pobieranie przez Banqup | łączenie transakcji z fakturami, także kilku faktur jedną wpłatą | cennik niepubliczny | narzędzie raczej dla większych firm i biur |
| Fakturoza | import MT940 | dopasowanie po numerze faktury lub KSeF, rachunku, NIP i kwocie | Darmowy: 5 faktur sprzedaży / mies., 1 wyciąg MT940 / mies. | więcej faktur i wyciągów w płatnym planie Firma |

## Kiedy Open Banking ma sens

O tym, kto może pobierać informacje z rachunku bankowego, rozstrzyga ustawa z 19 sierpnia 2011 r. o usługach płatniczych, zmieniona przy wdrożeniu dyrektywy PSD2. Przewidziano w niej AISP, czyli dostawcę świadczącego usługę dostępu do informacji o rachunku. Działalność ta jest regulowana i wymaga wpisu do rejestru prowadzonego przez Komisję Nadzoru Finansowego, lecz nie zezwolenia KNF. Dostęp działa, jak można się domyślić, wyłącznie przez internet i tylko wtedy, gdy sam rachunek jest dostępny online. Po zgodzie właściciela konta AISP przekazuje historię do programu do faktur; ręczny eksport MT940 albo CSV nie jest wtedy potrzebny przy każdej kolejnej synchronizacji. Za dzień rozpoczęcia działalności AISP uważa się dzień dokonania wpisu do rejestru.

## Źródła

- [Komisja Nadzoru Finansowego, „Informacje ogólne — działalność AISP”](https://www.knf.gov.pl/dla_rynku/procesy_licencyjne/platniczy/AISP/Informacje_Ogolne_Dzialalnosc_AISP); dostęp 5.11.2026.
- Firmowid: [firmowid.pl/cennik](https://firmowid.pl/cennik), [firmowid.pl/funkcje](https://firmowid.pl/funkcje); dostęp 22.10.2026.
- wFirma: [pomoc.wfirma.pl/-automatyczne-parowanie-transakcji-bankowych](https://pomoc.wfirma.pl/-automatyczne-parowanie-transakcji-bankowych), [pomoc.wfirma.pl/-sugestie-parowania-w-banku-jak-system-podpowiada-rozliczenia-przelewow](https://pomoc.wfirma.pl/-sugestie-parowania-w-banku-jak-system-podpowiada-rozliczenia-przelewow), [wfirma.pl/program-do-fakturowania](https://wfirma.pl/program-do-fakturowania); dostęp 24.10.2026.
- Fakturownia: [pomoc.fakturownia.pl/580203-Import-platnosci-z-banku](https://pomoc.fakturownia.pl/580203-Import-platnosci-z-banku), [pomoc.fakturownia.pl/164964491-Polaczenie-z-kontem-bankowym-w-Fakturowni](https://pomoc.fakturownia.pl/164964491-Polaczenie-z-kontem-bankowym-w-Fakturowni), [fakturownia.pl/cennik](https://fakturownia.pl/cennik); dostęp 26.10.2026.
- [Mobilna Faktura](https://mobilna-faktura.pl/cennik/); dostęp 5.11.2026.
- Afaktury: [afaktury.pl/wgranie-pliku-mt940,0,52,10,203](https://afaktury.pl/wgranie-pliku-mt940,0,52,10,203/), [afaktury.pl/cennik,0,31](https://afaktury.pl/cennik,0,31/); dostęp 23.10.2026.
- [ING Księgowość](https://www.ingksiegowosc.pl/fakturowanie/integracja-z-bankowoscia); dostęp 25.10.2026.
- [SaldeoSMART](https://www.saldeosmart.pl/automatyzacja-rozliczen-i-rozrachunkow); dostęp 24.10.2026.
- [Fakturoza](https://fakturoza.pl/); dostęp 11.11.2026.
