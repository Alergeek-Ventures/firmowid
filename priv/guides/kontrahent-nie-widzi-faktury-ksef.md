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

Spółka cywilna ma własny NIP, a każdy wspólnik swój. Kto wchodzi do Aplikacji Podatnika KSeF jako osoba fizyczna, ląduje w kontekście swojej jednoosobowej firmy i faktury wystawionej na spółkę tam nie zobaczy, dopóki nie przejdzie do kontekstu spółki. Pracownik zakupów czy biuro księgowe zalogują się profilem zaufanym bez problemu, a lista faktur i tak będzie pusta, jeśli nikt w firmie nie nadał im w KSeF uprawnienia do przeglądania faktur.

W wyszukiwarce MF zakupy i sprzedaż to dwie osobne listy, a datę można ustawić jako datę wystawienia albo datę przyjęcia do KSeF. Fakturę z 30 listopada, którą sprzedawca wysłał w trybie offline24 1 grudnia, klient filtrujący listopad po dacie przyjęcia po prostu przeoczy. Kod QR z PDF-a rozstrzyga sprawę szybciej niż wymiana maili: telefon otwiera stronę ministerstwa z fakturą z KSeF, razem z NIP nabywcy.

## Faktura dla gminy i jej jednostek

Od 2017 r. VAT w samorządach rozlicza gmina, więc szkoła czy przedszkole nie są nabywcą, tylko odbiorcą. Na fakturze FA(3) w polu nabywcy jest gmina, a jednostka idzie do sekcji Podmiot3 z rolą jednostki samorządu terytorialnego jako odbiorcy. Bez tego wpisu faktura trafia wyłącznie do gminy i do szkoły dociera dopiero wtedy, gdy ktoś w urzędzie ją przekaże.

## Kiedy faktury w KSeF nie ma i nie musi być

Do 31 grudnia 2026 r. faktury mogą powstawać poza KSeF w dwóch sytuacjach: gdy sprzedaż na fakturach nie przekracza 10 000 zł brutto miesięcznie ([jak liczyć ten limit](/poradnik/limit-10000-ksef)) i gdy fakturę drukuje kasa fiskalna ([paragon z NIP i faktura z kasy](/poradnik/kasa-fiskalna-paragon-z-nip-po-2026)). Taka faktura jest ważna, choć klient zna ją tylko z PDF-a albo wydruku. Od 1 stycznia 2027 r. oba wyjątki przestają działać.

## Numer KSeF

Faktura, która ma numer KSeF, jest w systemie, a według art. 106na ustawy o VAT za datę jej otrzymania przez nabywcę uznaje się dzień nadania tego numeru, niezależnie od tego, czy klient do KSeF zajrzał. Osoba prywatna albo firma z zagranicy, która dostaje fakturę poza systemem, otrzymuje ją w dniu, w którym faktura faktycznie do niej dotrze.

[Firmowid](/ksef), nasz program, pokazuje przy każdej fakturze numer KSeF i stan wysyłki, pozwala ponowić wysłanie odrzuconej faktury, a mail z fakturą do klienta wychodzi dopiero po nadaniu numeru.

![Sześć przyczyn, dla których klient nie widzi faktury w KSeF: błędny NIP nabywcy (korekta do zera i nowa faktura), plik odrzucony (wysłać ponownie), niewysłana faktura offline24, nabywca bez dostępu do KSeF (PDF z kodem QR), biuro rachunkowe bez uprawnienia i brak powiadomień z KSeF.](/images/guides/kontrahent-nie-widzi-faktury-ksef-przyczyny.webp)

## Źródła

- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/), dostęp 11.11.2026.
- Art. 106na i art. 106nda ustawy z 11 marca 2004 r. o podatku od towarów i usług.
- Uprawnienia dla biura: [dostęp do KSeF w JDG](/poradnik/dostep-do-ksef-jdg-i-ksiegowa).
