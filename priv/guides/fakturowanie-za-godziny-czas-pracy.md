---
title: "Faktura za godziny pracy: jak ją wystawić w KSeF"
description: "Faktura za godziny ma pozycję z jednostką godz., liczbą godzin i stawką. Jak wpisać niepełną godzinę, kiedy ją wystawić i co z raportem godzin w KSeF."
published: 2026-11-12
updated: 2026-11-24
category: firma-uslugowa
---

Kiedyś czas pracy zbieraliśmy w Excelu i w kilku innych narzędziach, a potem ktoś ręcznie oznaczał, w którym projekcie co się robiło. Teraz każdy pracownik ma w Firmowidzie przypisane projekty i wybiera ten, w którym zaczyna pracę: start, czas leci pod konkretnym projektem i nic więcej nie musi pamiętać, a projekt może w każdej chwili zmienić.

W widoku projektu widzimy, kto ile nad nim przepracował. Z tych godzin korzystamy przy wystawianiu faktury: sami albo prosząc asystenta, który przygotowuje szkic z liczbą godzin i stawką. To samo robi Claude podłączony przez MCP. Zawsze jest miejsce na zmianę danych, a do KSeF faktura idzie dopiero po naszym potwierdzeniu.

Klient dostaje fakturę, a do niej łatwo wygenerować raport godzin z projektu. Klienci są zadowoleni, że tak skrupulatnie i uczciwie liczymy czas pracy nad ich projektami.

## Jak wystawić fakturę za godziny pracy?

Godziny wpisuje się w pozycji faktury tak jak każdą inną usługę.

| Co | Pole w FA(3) | Opis w schemacie |
|---|---|---|
| Nazwa usługi | P_7 | „Nazwa (rodzaj) towaru lub usługi” |
| Jednostka, np. godz. | P_8A | „Miara dostarczonych towarów lub zakres wykonanych usług” |
| Liczba godzin | P_8B | „Ilość (liczba) dostarczonych towarów lub zakres wykonanych usług” |
| Stawka za godzinę | P_9A | „cena jednostkowa netto” |

Liczba godzin nie musi być całkowita. Schemat opisuje to pole tak: „Wartość numeryczna 22 znaki max, w tym 6 po przecinku”.

## Jak wpisać niepełną godzinę?

| Czas pracy | Na fakturze |
|---|---|
| 15 minut | 0,25 godz. |
| 30 minut | 0,5 godz. |
| 45 minut | 0,75 godz. |
| 1 godz. 20 min | 1,33 godz. |

## Czy do faktury w KSeF można dołączyć raport godzin?

Nie jako PDF. Ministerstwo Finansów: „Faktura w KSeF musi mieć format pliku XML. Dlatego nie można dołączyć PDF czy Worda”. O protokołach odbioru: „Protokoły odbioru nadal będą przekazywane poza KSeF”. Pliki PDF według MF „można oczywiście przekazywać kontrahentom, ale tylko poza systemem KSeF”.

O dopiskach na fakturze: „Dodatkowe informacje na fakturze będzie można zamieścić w polu DodatkowyOpis lub polu StopkaFaktury (zawiera ono maksymalnie 3500 znaków)”. O polu DodatkowyOpis ministerstwo pisze też: „Dane te mogą być podawane w odniesieniu do konkretnego wiersza faktury lub w odniesieniu do faktury jako całości”.

## Kiedy wystawić fakturę za godziny?

Serwis Biznes.gov.pl: „Fakturę wystawia się nie wcześniej niż 60. dnia przed dokonaniem dostawy towaru lub wykonaniem usługi, ale nie później niż 15. dnia miesiąca następującego po miesiącu, w którym dokonano dostawy lub wykonano usługę”.

Miesiąc rozliczenia ma w schemacie FA(3) własny element OkresFa, czyli „Okres, którego dotyczy faktura”.

## Godziny w Firmowidzie

Licznik czasu w [Firmowidzie](/funkcje/czas-pracy) działa w projekcie. Pole z tytułem sesji ma podpowiedź „Nad czym dzisiaj pracujesz?”. Raport godzin projektu pobiera się jako plik CSV. W kreatorze faktury jednostka to „szt.” albo „godz.”. Plan Darmowy obejmuje czas pracy w 3 projektach.

## Inne programy

| Program | Czas pracy w projektach | KSeF | Faktura przez asystenta AI |
|---|---|---|---|
| Firmowid | tak | tak | tak, po potwierdzeniu |
| Fakturownia | w module Zadania | tak | MCP do odczytu |
| inFakt | nie | tak | MCP we wszystkich planach |
| Kadromierz, RCPonline | tak | nie | nie |

MCP jest dostępny w płatnych planach, od planu [Przedsiębiorca](/cennik).

![Porównanie programów: Firmowid ma czas pracy w projektach, KSeF i fakturę przez asystenta AI po potwierdzeniu. Fakturownia ma KSeF i czas pracy w module Zadania, inFakt ma KSeF i MCP, ale nie czas pracy w projektach. Kadromierz i RCPonline mają czas pracy, ale nie KSeF.](/images/guides/faktura-za-godziny-czas-pracy-programy.webp)

## Źródła

- Firmowid: kod źródłowy (AGPL-3.0), moduły czasu pracy, faktur i MCP, stan 11.11.2026.
- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/) (wersja z 10.11.2026), dostęp 24.11.2026.
- Struktura logiczna FA(3), opisy pól P_7, P_8A, P_8B, P_9A i elementu OkresFa (schemat MF).
- [Biznes.gov.pl: Jak wystawiać faktury VAT](https://www.biznes.gov.pl/pl/portal/00239) (aktualizacja 01.07.2026), dostęp 24.11.2026.
- Cenniki i opisy funkcji Fakturowni, inFaktu, Kadromierza i RCPonline, stan na listopad 2026.
- Więcej o łączeniu programu z asystentem AI: [faktury w KSeF z ChatGPT i Claude](/funkcje/claude-chatgpt-mcp).
