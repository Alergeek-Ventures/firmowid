---
title: "Jak przetestować KSeF przed pierwszą prawdziwą fakturą"
description: "Środowisko testowe, Demo i produkcyjne w KSeF: które wybrać do nauki i jak przejść próbę bez skutków prawnych."
published: 2026-10-28
updated: 2026-10-30
---

KSeF ma trzy środowiska: testowe, przedprodukcyjne Demo i produkcyjne. Do nauki używaj dwóch pierwszych.

W środowisku testowym wszystko może być fikcyjne, łącznie z danymi logowania. W Demo logujesz się prawdziwymi danymi i masz swoje rzeczywiste uprawnienia, ale dane na fakturze nadal wpisujesz fikcyjne. Działania w środowisku testowym nie mają skutków prawnych, a faktury z Demo nie mają skutków podatkowych. Dane z obu środowisk są co jakiś czas usuwane.

## Które środowisko do czego

- **Testowe:** żeby poznać formularz i przejść cały proces bez logowania się jako firma.
- **Demo:** żeby przed pierwszą fakturą sprawdzić, czy działa twoje logowanie i nadane uprawnienia.
- **Produkcyjne:** tylko do prawdziwych faktur. Nie wysyłaj tam niczego na próbę.

## Próba krok po kroku

1. Otwórz testową wersję Aplikacji Podatnika KSeF 2.0.
2. Wpisz fikcyjne dane sprzedawcy, nabywcy i transakcji.
3. Wystaw i wyślij fakturę, sprawdź status, pobierz dokument i UPO (Urzędowe Poświadczenie Odbioru).
4. W Demo sprawdź osobno logowanie i uprawnienia, nadal bez danych prawdziwego kontrahenta.

## XML i PDF

Faktura w KSeF to plik XML według schemy FA(3). PDF jest tylko jej czytelną wersją i nie zastępuje XML-a. Więcej w poradniku [co to jest KSeF i e-faktura](/poradnik/co-to-jest-ksef-i-e-faktura), a całą drogę na produkcji opisuje [pierwsza faktura w KSeF](/poradnik/pierwsza-faktura-ksef).

## Źródła

- [MF: wersja testowa Aplikacji Podatnika KSeF 2.0](https://ksef.podatki.gov.pl/aplikacja-podatnika-ksef-20/aplikacja-podatnika-ksef-20-wersja-testowa/), dostęp 9.10.2026.
- [MF: wersja przedprodukcyjna Demo](https://ksef.podatki.gov.pl/aplikacja-podatnika-ksef-20/aplikacja-podatnika-ksef-20-wersja-przedprodukcyjna-demo/), dostęp 9.10.2026.
- [MF: faktura ustrukturyzowana i FA(3)](https://ksef.podatki.gov.pl/informacje-ogolne-ksef-20/faktura-ustrukturyzowana-i-struktura-logiczna-fa/), dostęp 9.10.2026.
