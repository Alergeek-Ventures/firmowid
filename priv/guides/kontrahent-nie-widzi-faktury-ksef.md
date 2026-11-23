---
title: "Kontrahent nie widzi faktury w KSeF? 6 przyczyn i co zrobić"
description: "Najczęściej to błędny NIP nabywcy: KSeF go nie sprawdza i faktura trafia do innej firmy. Inne przyczyny: plik odrzucony, offline24, brak uprawnień biura."
published: 2026-11-12
updated: 2026-11-23
category: ksef-w-praktyce
---

Ministerstwo Finansów podaje w odpowiedziach na pytania podatników, że KSeF nie sprawdza danych kontrahenta, więc faktura z błędnym NIP nabywcy zostaje przyjęta i trafia do firmy, do której ten numer należy, a właściwy klient jej nie widzi.

| Przyczyna | Co widzi wystawca | Co zrobić |
|---|---|---|
| Błędny NIP nabywcy | faktura ma numer KSeF | [korekta do zera](/poradnik/korekta-faktury-ksef) i nowa faktura z poprawnym NIP |
| Plik odrzucony przez KSeF | brak numeru KSeF, komunikat o błędzie | poprawić plik i wysłać ponownie, bez korekty |
| Faktura offline24 jeszcze niewysłana | brak numeru KSeF | wysłać najpóźniej następnego dnia roboczego ([tryb offline](/poradnik/tryb-offline-ksef)) |
| Nabywca to osoba prywatna albo firma z zagranicy | faktura w KSeF, nabywca bez dostępu | przekazać PDF z kodem QR |
| Biuro rachunkowe nabywcy | faktura w systemie | nabywca nadaje biuru uprawnienie do przeglądania faktur |
| Brak powiadomień z KSeF | faktura w systemie | wysłać klientowi PDF albo link |

## Co sprawdzić po stronie klienta

Zanim wystawca zacznie cokolwiek korygować, warto poprosić klienta o trzy sprawdzenia, bo często faktura jest w systemie, tylko nie tam, gdzie on patrzy.

Pierwsze to kontekst logowania. Wspólnik spółki cywilnej zalogowany do Aplikacji Podatnika KSeF swoim NIP widzi faktury własnej działalności. Faktura wystawiona na NIP spółki leży w kontekście spółki, na który trzeba się przełączyć albo do którego trzeba mieć uprawnienie.

Drugie to uprawnienia. Pracownik działu zakupów albo biuro księgowe zobaczą faktury kosztowe firmy dopiero po tym, jak właściciel nada im w KSeF uprawnienie do przeglądania faktur. Samo zalogowanie się podpisem czy profilem zaufanym takiego dostępu nie daje.

Trzecie to wyszukiwarka. Faktury zakupowe i sprzedażowe są w aplikacji MF osobnymi listami, a zakres dat można liczyć od dnia wystawienia albo od dnia przyjęcia faktury przez KSeF. Dokument wystawiony ostatniego dnia miesiąca i wysłany dzień później w trybie offline wypada poza zakres ustawiony na poprzedni miesiąc według daty przyjęcia.

Gdy klient nadal nic nie widzi, najszybszym dowodem jest kod QR z wizualizacji faktury. Po zeskanowaniu telefonem otwiera stronę Ministerstwa Finansów, która pokazuje, że dokument jest w KSeF, razem z jego danymi, więc rozmowa o tym, czy faktura w ogóle wyszła, kończy się po minucie, a zostaje tylko pytanie, na jaki NIP trafiła.

## Faktura dla gminy i jej jednostek

Szkoła, przedszkole czy ośrodek pomocy społecznej nie są nabywcą na fakturze. Nabywcą jest gmina ze swoim NIP, a jednostkę wpisuje się w strukturze FA(3) jako podmiot trzeci w roli odbiorcy. Gdy sprzedawca pominie to pole, faktura trafia do gminy, a księgowość jednostki jej nie znajdzie, dopóki gmina jej nie przekaże.

## Kiedy faktury w KSeF nie ma i nie musi być

Do 31 grudnia 2026 r. firma, której sprzedaż na fakturach nie przekracza 10 000 zł brutto w miesiącu, może je wystawiać poza KSeF ([jak liczyć ten limit](/poradnik/limit-10000-ksef)). Poza systemem mogą też powstawać faktury drukowane z kasy fiskalnej ([paragon z NIP i faktura z kasy](/poradnik/kasa-fiskalna-paragon-z-nip-po-2026)). Klient dostaje wtedy PDF albo wydruk, w KSeF nic nie znajdzie, a dokument i tak jest ważną fakturą. Oba wyjątki kończą się 1 stycznia 2027 r.

## Numer KSeF

Faktura, która ma numer KSeF, jest w systemie, a według art. 106na ustawy o VAT za datę jej otrzymania przez nabywcę uznaje się dzień nadania tego numeru, niezależnie od tego, czy klient do KSeF zajrzał. Osoba prywatna albo firma z zagranicy, która dostaje fakturę poza systemem, otrzymuje ją w dniu, w którym faktura faktycznie do niej dotrze.

[Firmowid](/ksef), nasz program, pokazuje przy każdej fakturze numer KSeF i stan wysyłki, pozwala ponowić wysłanie odrzuconej faktury, a mail z fakturą do klienta wychodzi dopiero po nadaniu numeru.

![Sześć przyczyn, dla których klient nie widzi faktury w KSeF: błędny NIP nabywcy (korekta do zera i nowa faktura), plik odrzucony (wysłać ponownie), niewysłana faktura offline24, nabywca bez dostępu do KSeF (PDF z kodem QR), biuro rachunkowe bez uprawnienia i brak powiadomień z KSeF.](/images/guides/kontrahent-nie-widzi-faktury-ksef-przyczyny.webp)

## Źródła

- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/), dostęp 11.11.2026.
- Art. 106na i art. 106nda ustawy z 11 marca 2004 r. o podatku od towarów i usług.
- Uprawnienia dla biura: [dostęp do KSeF w JDG](/poradnik/dostep-do-ksef-jdg-i-ksiegowa).
