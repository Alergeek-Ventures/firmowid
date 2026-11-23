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

Spółka cywilna ma własny NIP, a każdy wspólnik swój. Wspólnik loguje się do Aplikacji Podatnika KSeF jako on sam i widzi faktury swojej JDG. Faktura na spółkę czeka piętro wyżej, w kontekście spółki. A pracownik? Profil zaufany wpuszcza go do KSeF, tylko że faktur firmy nie zobaczy, dopóki właściciel nie nada mu uprawnienia do przeglądania faktur. Z biurem księgowym jest dokładnie tak samo.

Druga pułapka siedzi w wyszukiwarce. Zakupy i sprzedaż są w aplikacji MF osobno, a filtr dat działa albo po dacie wystawienia, albo po dacie przyjęcia do KSeF. Faktura z 30 listopada wysłana offline 1 grudnia? W listopadzie liczonym po dacie przyjęcia jej nie ma. Wtedy wystarczy wysłać klientowi kod QR z PDF-a i po sprawie: telefon pokaże fakturę na stronie ministerstwa, razem z NIP, na który poszła.

## Faktura dla gminy i jej jednostek

Od 2017 r. VAT w samorządach rozlicza gmina, więc szkoła czy przedszkole nie są nabywcą, tylko odbiorcą. W FA(3) gmina idzie w pole nabywcy, a szkoła do Podmiot3, z rolą odbiorcy przewidzianą dla jednostek samorządu. Bez Podmiot3 fakturę ma tylko gmina i szkoła czeka, aż urząd ją prześle.

## Kiedy faktury w KSeF nie ma i nie musi być

Bywa też, że faktury w KSeF nie ma, bo nie musi jej tam być. Do końca 2026 r. firmy, które sprzedają na fakturach za mniej niż 10 000 zł brutto miesięcznie, mogą wystawiać je po staremu ([jak liczyć ten limit](/poradnik/limit-10000-ksef)). Po staremu wolno też drukować faktury z kasy fiskalnej ([paragon z NIP i faktura z kasy](/poradnik/kasa-fiskalna-paragon-z-nip-po-2026)). Klient ma PDF albo papier i to wystarcza. Od stycznia 2027 r. ta furtka się zamyka.

## Numer KSeF

Faktura, która ma numer KSeF, jest w systemie, a według art. 106na ustawy o VAT za datę jej otrzymania przez nabywcę uznaje się dzień nadania tego numeru, niezależnie od tego, czy klient do KSeF zajrzał. Osoba prywatna albo firma z zagranicy, która dostaje fakturę poza systemem, otrzymuje ją w dniu, w którym faktura faktycznie do niej dotrze.

[Firmowid](/ksef), nasz program, pokazuje przy każdej fakturze numer KSeF i stan wysyłki, pozwala ponowić wysłanie odrzuconej faktury, a mail z fakturą do klienta wychodzi dopiero po nadaniu numeru.

![Sześć przyczyn, dla których klient nie widzi faktury w KSeF: błędny NIP nabywcy (korekta do zera i nowa faktura), plik odrzucony (wysłać ponownie), niewysłana faktura offline24, nabywca bez dostępu do KSeF (PDF z kodem QR), biuro rachunkowe bez uprawnienia i brak powiadomień z KSeF.](/images/guides/kontrahent-nie-widzi-faktury-ksef-przyczyny.webp)

## Źródła

- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/), dostęp 11.11.2026.
- Art. 106na i art. 106nda ustawy z 11 marca 2004 r. o podatku od towarów i usług.
- Uprawnienia dla biura: [dostęp do KSeF w JDG](/poradnik/dostep-do-ksef-jdg-i-ksiegowa).
