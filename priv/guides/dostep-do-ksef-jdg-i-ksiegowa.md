---
title: "Dostęp do KSeF w jednoosobowej firmie i uprawnienia dla księgowej"
description: "JDG ma dostęp do KSeF automatycznie. Jak się zalogować, kiedy potrzebny jest ZAW-FA, dlaczego certyfikatu nie przekazuje się księgowej i jak nadać uprawnienia biuru."
published: 2026-11-12
updated: 2026-11-12
category: ksef-w-praktyce
---

Z dostępem do KSeF w jednoosobowej działalności wiąże się mniej formalności, niż zakłada wielu przedsiębiorców, bo osoba fizyczna z NIP otrzymuje w systemie uprawnienia właścicielskie automatycznie i nie składa w tej sprawie żadnego zgłoszenia. Według Ministerstwa Finansów loguje się ona Podpisem Zaufanym albo kwalifikowanym podpisem elektronicznym, przy czym podpis, który nie zawiera ani NIP, ani PESEL, trzeba najpierw powiązać z podatnikiem na formularzu ZAW-FA. Spółka bez pieczęci kwalifikowanej z NIP również składa ZAW-FA i wskazuje w nim osobę, która będzie obsługiwać KSeF.

## Token i certyfikat

Do połączenia programu do faktur z KSeF służy token albo certyfikat KSeF, które użytkownik generuje w Aplikacji Podatnika KSeF. Certyfikat typu 2 jest ponadto potrzebny do wygenerowania drugiego kodu QR, z napisem „CERTYFIKAT”, na fakturze z trybu offline przekazywanej nabywcy przed jej przesłaniem do systemu. W Firmowidzie, naszym programie do faktur, typ połączenia wybiera się w ustawieniach KSeF, a przy certyfikacie zapisana jest data jego wygaśnięcia.

## Uprawnienia dla księgowej

Na pytanie przedsiębiorczyni, czy może przekazać księgowej pobrany certyfikat, ministerstwo odpowiada przecząco, bo certyfikat jest osobistym poświadczeniem tożsamości i korzysta z niego tylko osoba, na którą go wydano. Księgowej albo pracownikowi nadaje się zamiast tego uprawnienie do wystawiania lub przeglądania faktur, w Aplikacji Podatnika KSeF albo w programie połączonym z systemem przez API. Biuru rachunkowemu można nadać uprawnienie jako całemu podmiotowi i zaznaczyć, że wolno mu przekazywać je swoim pracownikom, dzięki czemu przedsiębiorca nie musi wskazywać każdej osoby z biura z osobna.

![Właściciel JDG ma uprawnienia w KSeF automatycznie i loguje się Podpisem Zaufanym albo kwalifikowanym. Program do faktur łączy się tokenem albo certyfikatem z Aplikacji Podatnika KSeF. Księgowej albo biuru właściciel nadaje uprawnienia, nie przekazuje certyfikatu.](/images/guides/dostep-do-ksef-wlasciciel-program-ksiegowa.webp)

## Źródła

- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/), dostęp 11.11.2026.
- [MF: Krok po kroku, JDG i MŚP](https://ksef.podatki.gov.pl/krok-po-kroku-jdg-i-msp/), dostęp 10.11.2026.

*To informacja ogólna, nie porada podatkowa.*
