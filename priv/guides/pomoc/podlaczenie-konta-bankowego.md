---
title: "Jak podłączyć konto bankowe do Firmowida: krok po kroku"
description: "Podłączenie banku przez Open Banking w kilka kliknięć, ze zrzutem ekranu przy każdym kroku. Do tego odnawianie zgody co 90 dni i konto dodane ręcznie."
published: 2026-11-18
updated: 2026-11-18
category: bank-i-platnosci
---

Bank podłączasz raz: wybierasz go z listy, logujesz się na stronie banku i tam dajesz zgodę. Trwa to kilkanaście sekund. Hasło do bankowości zostaje w banku, a Firmowid dostaje przez GoCardless tylko dostęp do odczytu sald i historii.

**Co trzeba mieć:** rolę administratora w Firmowidzie i dostęp do bankowości elektronicznej rachunku.

## Krok 1. Otwórz „Konta bankowe” i kliknij „Nowe konto”

W pasku bocznym, w sekcji „Firma”, kliknij **Konta bankowe**, a potem **Nowe konto**.

![Pozycja „Konta bankowe” w pasku bocznym i przycisk „Nowe konto”](/images/guides/pomoc/bank-1-konta-bankowe.webp)

## Krok 2. Wybierz swój bank

Otworzy się strona „Dodaj konto bankowe” z kaflami banków. Kliknij swój bank. W miejscu listy pojawi się link „Kliknij, aby potwierdzić połączenie”.

![Strona „Dodaj konto bankowe” z kaflami banków](/images/guides/pomoc/bank-2-wybor-banku.webp)

## Krok 3. Potwierdź zgodę w banku

Kliknij link. Przejdziesz na stronę banku, gdzie logujesz się tak jak zwykle i wskazujesz rachunki, które Firmowid ma widzieć. Zgoda obejmuje salda, szczegóły rachunku i transakcje, tylko do odczytu.

## Krok 4. Wróć do Firmowida

Po zatwierdzeniu wrócisz na listę kont z komunikatem „Konto bankowe zostało poprawnie połączone.”. Przez chwilę zobaczysz „Trwa konfiguracja połączenia bankowego.”, a potem karty kont. Firmowid pobiera historię do 90 dni wstecz, a nowe przelewy co drugi dzień.

Rachunek w kilku walutach pojawi się jako kilka kont. W menu konta wybierz „Domyślne dla {waluta}”, żeby wskazać rachunek, który ma się podstawiać na fakturach w tej walucie.

## Po 90 dniach: „Połącz ponownie”

Zgoda w banku jest ważna 90 dni. Gdy wygaśnie, karta konta pokaże „Konto rozłączone”, a w Skrzynce pojawi się „synchronizacja wstrzymana” z przyciskiem „Odnów zgodę”. Kliknij **Połącz ponownie** i potwierdź zgodę w banku jeszcze raz. Historia, dopasowania i nazwa konta zostają.

![Karta konta ze stanem „Konto rozłączone” i przyciskiem „Połącz ponownie”](/images/guides/pomoc/bank-4-polacz-ponownie.webp)

## Bank, którego nie ma na liście

Kliknij **Dodaj ręcznie** i podaj nazwę konta, właściciela, IBAN i walutę. Takie konto możesz wybrać na fakturze jako rachunek do wpłat, ale nie pobiera przelewów, więc faktur z nim program nie oznaczy sam jako opłaconych.

![Przycisk „Dodaj ręcznie”](/images/guides/pomoc/bank-5-dodaj-recznie.webp)

## Dobrze wiedzieć

- Firmowid nie wczytuje wyciągów MT940 ani CSV i nie zleca przelewów.
- Nie ma przycisku ręcznego odświeżenia; nowe przelewy przyjdą przy kolejnej synchronizacji.
- Limit w cenniku liczy banki, nie rachunki; konta dodane ręcznie się nie liczą ([cennik](/cennik)).
- Gdy lista banków się nie wczyta, odśwież stronę po kilku minutach. Gdy po powrocie z banku zobaczysz „Połączenie z bankiem nie zostało utworzone w tym momencie.”, zacznij od kroku 1.

Zobacz też: [Bank i dopasowanie przelewów do faktur](/funkcje/bank) · [Jak działa dopasowanie przelewów](/pomoc/dopasowanie-przelewow) · [Revolut i Wise w programie do faktur z KSeF](/poradnik/revolut-wise-program-do-faktur)
