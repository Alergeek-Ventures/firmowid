---
title: "Faktura dla osoby prywatnej a KSeF: czy trzeba ją wysłać?"
description: "Faktury dla osoby prywatnej nie trzeba wysyłać do KSeF. Można ją tam wystawić dobrowolnie, bez NIP nabywcy, i przekazać klientowi jako PDF z kodem QR."
published: 2026-11-23
updated: 2026-11-23
category: ksef-w-praktyce
---

Faktury dla osoby prywatnej nie trzeba wysyłać do KSeF. Ministerstwo Finansów odpowiada na to pytanie jednym zdaniem: „Wystawianie w KSeF faktur na rzecz konsumentów nie jest obowiązkowe”. Sprzedawca może taką fakturę wystawić w systemie dobrowolnie, bez NIP nabywcy, i wtedy sam przekazuje ją klientowi.

| Nabywca | Faktura w KSeF | Jak trafia do nabywcy |
|---|---|---|
| Osoba prywatna (konsument) | dobrowolnie | wydruk albo PDF, przy fakturze z KSeF z kodem QR |
| Przedsiębiorca kupujący na prywatny użytek | dobrowolnie | wydruk albo PDF, przy fakturze z KSeF z kodem QR |
| Osoba na działalności nierejestrowanej, bez NIP | obowiązkowo | poza systemem, z kodem QR, bo bez NIP nie pobierze jej z KSeF |
| Firma z NIP | obowiązkowo | w KSeF |

## Czy fakturę na osobę prywatną trzeba wysłać do KSeF?

Nie. W podręczniku KSeF 2.0 faktury „na rzecz osoby fizycznej nieprowadzącej działalności gospodarczej (konsumenta)” są na liście wyłączeń z obowiązku, które wynikają ze statusu stron transakcji. Dla tego wyłączenia w harmonogramie MF nie ma daty końcowej, inaczej niż dla limitu 10 000 zł i faktur z kas rejestrujących, które kończą się 31 grudnia 2026 r.

Tak samo ministerstwo traktuje zakup prywatny przedsiębiorcy. O fakturach dla osób prowadzących działalność, które dotyczą zakupu „na użytek prywatny (czyli stanowiące w istocie transakcję B2C)”, MF pisze, że ich wystawianie „będzie w KSeF dobrowolne”.

## Czy w KSeF można wystawić fakturę na osobę prywatną?

Można. Sprzedawca sam decyduje, a decyzja nie wiąże go na przyszłość. W odpowiedziach MF czytamy: „Przepisy nie nakładają wymogu, wskazującego, że jeśli podatnik zdecyduje się wystawiać faktury konsumenckie w KSeF to musi już wystawiać w nim wszystkie tego typu faktury”.

Dotyczy to także faktury do paragonu. Przedsiębiorcy z kasą fiskalną online, który chce wszystkie faktury wystawiać w systemie, ministerstwo odpisało, że „może taką fakturę wystawić w KSeF (w tym fakturę do paragonu)”. Zasady dla kas zmieniają się od 2027 r., o czym jest osobny tekst: [kasa fiskalna i paragon z NIP po 2026 r.](/poradnik/kasa-fiskalna-paragon-z-nip-po-2026)

## Jak wystawić fakturę w KSeF dla osoby fizycznej bez NIP?

W danych nabywcy wpisuje się imię, nazwisko i adres, a zamiast identyfikatora podatkowego zaznacza jego brak. W strukturze e-faktury służy do tego pole BrakID z wartością „1” w części Podmiot2. Numeru PESEL się nie podaje, bo według MF „struktura e-Faktury nie przewiduje pola dedykowanego wskazaniu numeru PESEL”.

| Pole | Faktura dla firmy | Faktura dla osoby prywatnej |
|---|---|---|
| Nazwa nabywcy | nazwa firmy | imię i nazwisko |
| Adres | tak | tak |
| NIP nabywcy | tak | nie, pole BrakID |
| PESEL | nie | nie |
| Stawka VAT | według towaru lub usługi | według towaru lub usługi |

NIP sprzedawcy jest zawsze obowiązkowy. Ministerstwo pisze wprost: „W KSeF nie ma technicznej możliwości wystawienia faktury bez NIP sprzedawcy”.

## Jak osoba prywatna dostaje fakturę z KSeF?

Konsument nie loguje się do systemu i niczego z niego nie pobiera. Sprzedawca, który wystawił fakturę w KSeF, według MF „przekaże ją nabywcy w uzgodniony z nim sposób np. w postaci wydruku lub jako plik pdf wysłany w wiadomości e-mail, opatrzony dodatkowo kodem QR z oznaczeniem numeru KSeF”.

Na forach pada pytanie, czy osoba fizyczna musi kupić program albo abonament, żeby odbierać faktury za telewizor czy laptop. Nie musi. Jeżeli sprzedawca nie korzysta przy takiej sprzedaży z KSeF, faktury według ministerstwa „będą mogły być nadal wystawione papierowo lub elektronicznie (np. wysłane mailem)”.

Faktura konsumencka może też powstać w trybie offline24. Wydana klientowi przed przesłaniem do systemu ma dwa kody z napisami OFFLINE i CERTYFIKAT. Więcej: [tryb offline w KSeF](/poradnik/tryb-offline-ksef).

## Kiedy można wystawić fakturę na osobę fizyczną?

Na jej żądanie. Art. 106b ust. 3 ustawy o VAT daje nabywcy 3 miesiące na zgłoszenie żądania, licząc od końca miesiąca, w którym dostarczono towar, wykonano usługę albo otrzymano zapłatę. KSeF tych terminów nie zmienił, co MF potwierdza w odpowiedzi dla jednostki zwolnionej z VAT: wystawianie faktur B2C odbywa się „na żądanie konsumenta”.

## Czy faktury dla osób prywatnych liczą się do limitu 10 000 zł?

Nie. Do końca 2026 r. najmniejsze firmy wystawiają faktury poza KSeF, dopóki sprzedaż na fakturach nie przekroczy 10 000 zł brutto w miesiącu. Ministerstwo wyjaśnia, że do limitu wlicza się wyłącznie faktury, które podatnik musiałby wystawić w systemie, i dodaje: „Faktury konsumenckie nie są objęte obowiązkowym KSeF”. Poza limitem zostaje też sprzedaż dla osób prywatnych zarejestrowana tylko na kasie. Jak liczyć próg, opisuje tekst [limit 10 000 zł w KSeF](/poradnik/limit-10000-ksef).

## Jak wystawić fakturę jako działalność nierejestrowana?

Tu są dwie różne sytuacje.

| Sytuacja | Co mówi MF |
|---|---|
| Kupuje osoba na działalności nierejestrowanej, bez NIP | faktura w KSeF, bo „nabywca ten jest podatnikiem w rozumieniu ustawy o VAT”; w danych nabywcy BrakID |
| Sprzedaje osoba bez NIP, która ma obowiązek wystawić fakturę w KSeF | potrzebny NIP sprzedawcy; MF wskazuje zgłoszenie NIP-7 i VAT-R w urzędzie skarbowym |
| Sprzedaż na fakturach do 10 000 zł brutto w miesiącu | do końca 2026 r. bez obowiązku KSeF |

Kłopot zostaje po stronie sprzedawcy. Jeden z nich napisał na forum swojego programu do faktur: „Powodzenia w odróżnianiu (po imieniu i nazwisku?), kiedy kupuje rolnik/osoba na działalność niezarejestrowaną, a kiedy osoba na użytek prywatny”. Odpowiedzi MF tego nie rozstrzygają.

## Faktura dla osoby prywatnej w Firmowidzie

Firmowid, nasz [program do KSeF](/ksef), obsługuje faktury zarówno dla firm, jak i dla osób prywatnych. Po tym, jak się [zarejestrujesz](/zarejestruj), masz 60 darmowych dni na dowolny plan.

W kreatorze typ nabywcy to „Firma / Jednoosobowa Działalność Gospodarcza” albo „Osoba prywatna”. Przy osobie prywatnej jest pole „PESEL (opcjonalnie)”. Numer drukuje się na PDF, do KSeF nie jest wysyłany. Po zaznaczeniu „Wyślij fakturę e-mailem do kontrahenta po otrzymaniu numeru KSeF” klient dostaje PDF z kodem QR.

Faktury poza KSeF w Firmowidzie nie ma: każda wystawiona faktura idzie do systemu, konsumencka też. Nie da się jej też zlecić przez Claude ani ChatGPT. Serwer MCP odpowiada wtedy: „Przez MCP można wystawiać faktury wyłącznie dla firm z numerem NIP lub jego zagranicznym odpowiednikiem. Fakturę dla osoby prywatnej wystaw w aplikacji Firmowid”.

![Faktura dla osoby prywatnej i dla przedsiębiorcy kupującego prywatnie jest w KSeF dobrowolna, a nabywca dostaje wydruk albo PDF, przy fakturze z KSeF z kodem QR. Faktura dla osoby na działalności nierejestrowanej bez NIP i dla firmy z NIP jest w KSeF obowiązkowa. Do KSeF nie trafia NIP ani PESEL osoby prywatnej, w danych nabywcy zaznacza się pole BrakID.](/images/guides/faktura-osoba-prywatna-ksef-kiedy-obowiazkowa.webp)

## Źródła

- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/) (wersja z 10.11.2026), dostęp 23.11.2026.
- [MF: Podręcznik KSeF 2.0, cz. I](https://ksef.podatki.gov.pl/media/dmrfdixs/podrecznik-ksef-20-cz-i-rozpoczecie-korzystania-z-ksef-06082026.pdf) (wersja z sierpnia 2026 r., wyłączenia z obowiązku i harmonogram), dostęp 23.11.2026.
- Ustawa z 11 marca 2004 r. o podatku od towarów i usług, art. 106b ust. 3.

*To informacja ogólna, nie porada podatkowa.*
