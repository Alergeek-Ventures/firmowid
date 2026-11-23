---
title: "Tryb offline w KSeF: co zrobić, gdy nie możesz wysłać faktury"
description: "Tryb offline24, niedostępność KSeF i awaria: kiedy wolno wystawić fakturę poza systemem i do kiedy trzeba ją dosłać. Stan na listopad 2026."
published: 2026-11-06
updated: 2026-11-23
category: ksef-w-praktyce
---

O tym, od kiedy KSeF obowiązuje poszczególne firmy, pisaliśmy już [w poradniku o terminach](/poradnik/co-to-jest-ksef-i-e-faktura), dlatego tu tylko krótko przypomnimy najważniejsze. Faktury kosztowe odbiera się przez system od 1 lutego 2026 r., a większość przedsiębiorców wystawia w nim faktury od 1 kwietnia. Najmniejsze firmy, ze sprzedażą do [10 000 zł brutto miesięcznie](/poradnik/limit-10000-ksef), mają czas do końca roku. System działa, jak można się domyślić, wyłącznie online, więc ustawodawca musiał przewidzieć, co robić, gdy w biurze nie ma internetu albo przestaje działać program do faktur.

## Tryb offline24

Na taką okoliczność jest tryb offline24, opisany w art. 106nda ustawy o VAT. Fakturę wystawia się wtedy poza KSeF i wysyła do systemu najpóźniej w następnym dniu roboczym po dniu wystawienia. Z trybu offline24 możesz skorzystać z dowolnego powodu po swojej stronie i nie musisz go nigdzie zgłaszać.

## Gdy nie działa sam KSeF

Inaczej jest wtedy, gdy nie działa sam KSeF, a Ministerstwo Finansów ogłosi niedostępność systemu w Biuletynie Informacji Publicznej. Wtedy faktury wystawione w czasie przerwy trzeba dosłać do KSeF w następnym dniu roboczym po jej zakończeniu. Jeśli w tym czasie MF ogłosi jeszcze awarię KSeF, termin wydłuża się do 7 dni roboczych od jej zakończenia. Przy awarii całkowitej, o której ministerstwo informuje w radiu, telewizji i prasie, faktur do KSeF się nie dosyła.

![Cztery sytuacje i terminy dosłania faktury do KSeF. Tryb offline24: następny dzień roboczy po dniu wystawienia. Niedostępność ogłoszona w BIP: następny dzień roboczy po zakończeniu przerwy. Awaria KSeF: 7 dni roboczych od zakończenia. Awaria całkowita: faktur się nie dosyła.](/images/guides/tryb-offline-ksef-terminy-dosylania-faktur.webp)
*Terminy według Ministerstwa Finansów, stan na listopad 2026.*

## Kiedy faktura w KSeF jest offline?

Wtedy, gdy do systemu trafia później niż w dniu, który wystawca wpisał jako datę wystawienia. Nie trzeba niczego zaznaczać. Ministerstwo opisuje to tak: „Jeżeli zrobisz to dopiero następnego dnia, system potraktuje ją jako fakturę wystawioną w trybie offline24”.

| Data w polu P_1 a dzień wysyłki | Tryb | Data wystawienia |
|---|---|---|
| Ten sam dzień | online | dzień wysyłki |
| Wysyłka później | offline24 | data z pola P_1 |
| Data z przyszłości | brak | plik odrzucony |

Podręcznik KSeF 2.0 pokazuje to na przykładzie: w polu P_1 jest 2 lutego 2026 r., plik trafia do systemu 3 lutego i tego dnia dostaje numer KSeF. MF rozstrzyga: „Fakturę uznaje się za wystawioną w trybie offline24”, z datą wystawienia 2 lutego.

## Która data jest datą wystawienia faktury offline?

Data z pola P_1. To pytanie wraca na forach biur rachunkowych, na przykład w takiej postaci: „w polu P_1 (wypełnionym przez wystawcę) widnieje data 02.03.2026, a numer KSeF został nadany dopiero 03.03.2026”. Podręcznik odpowiada, że w takim przypadku „datą jej wystawienia będzie data z pola P_1”.

Dla nabywcy liczy się druga data. W odpowiedziach MF czytamy: „Zgodnie z ogólną zasadą fakturę ustrukturyzowaną uznaje się za otrzymaną w dniu przydzielenia numeru KSeF”. Stąd wątpliwość z tego samego forum: „Czy kierując się datą na wizualizacji, nie odliczę za wcześnie VAT, skoro do KSeF wysłano w następnym m-cu?”.

| Data | Skąd | Dla kogo ważna |
|---|---|---|
| Wystawienia | pole P_1 | sprzedawca |
| Otrzymania | dzień nadania numeru KSeF | nabywca |

## Faktura wysłana po terminie

System jej nie odrzuca. Podręcznik stwierdza: „Przesłanką odrzucenia pliku XML przez system nie jest jednak wskazanie w polu P_1 daty wcześniejszej niż data przesłania pliku XML do KSeF”. Na forum ktoś opisał taki przypadek: „Ja już mam fakturę wystawiona 9.02 i przesłana do ksef 27.02”.

Przyjęcie pliku nie znaczy, że termin został dotrzymany. W trybie offline24 jest nim następny dzień roboczy po dniu wystawienia, a sankcje za jego przekroczenie opisuje tekst [kary za KSeF w 2027 r.](/poradnik/kary-ksef-2027)

## Czy faktura offline ma numer KSeF?

Dopiero po przesłaniu do systemu. Do tego czasu faktura wydana nabywcy ma dwa kody QR z napisami „OFFLINE” i „CERTYFIKAT”, a po nadaniu numeru jeden kod z numerem KSeF.

## W programie do faktur

W praktyce większość programów do faktur, w tym nasz [Firmowid](/ksef), pozwala ponowić wysyłkę faktury, której nie udało się przesłać, więc po powrocie internetu wystarczy to zrobić przed upływem terminu.

Sam Firmowid faktur offline nie wystawia. Bez połączenia z KSeF pokazuje komunikat „Połącz z KSeF przed wystawieniem tej faktury” i pozwala zapisać fakturę jako wersję roboczą.

## Najczęstsze pytania

![Cztery zasady dla faktury wystawionej offline: internet nie jest potrzebny w chwili wystawienia, datą wystawienia jest data z pola P_1, podatnik VAT odbiera fakturę przez KSeF, a konsument i kontrahent zagraniczny dostają ją z kodami QR OFFLINE i CERTYFIKAT. Korektę wystawia się po nadaniu numeru KSeF.](/images/guides/faktura-offline-ksef-data-klient-korekta.webp)
*Najczęstsze pytania w skrócie.*

### Czy przy trybie offline24 trzeba mieć internet w chwili wystawiania faktury?

Nie. Do KSeF wysyłasz ją później, najpóźniej w następnym dniu roboczym po dniu wystawienia.

### Jaką datę wystawienia ma taka faktura?

Datą wystawienia jest data podana na fakturze w polu P_1, nawet jeśli do KSeF trafi ona dzień później.

### Jak klient dostaje fakturę wystawioną offline?

Nabywca będący podatnikiem VAT odbiera ją przez KSeF, a datą otrzymania jest dzień nadania numeru. Konsumentowi i kontrahentowi zagranicznemu udostępnia się ją w sposób uzgodniony, a jeśli jeszcze przed wysłaniem do KSeF, to z dwoma kodami QR: „OFFLINE” i „CERTYFIKAT”.

### Czy można skorygować fakturę z trybu offline?

Tak, ale korektę wystawia się dopiero po nadaniu fakturze pierwotnej numeru KSeF.

## Źródła

- [Ministerstwo Finansów, Podręcznik KSeF 2.0, cz. II, rozdziały 1.4 i 1.6](https://ksef.podatki.gov.pl/media/rronoxyt/podrecznik-ksef-20-cz-ii-wystawianie-i-otrzymywanie-faktur-w-ksef-06082026.pdf) (wersja z sierpnia 2026 r.); dostęp 23.11.2026.
- [Ministerstwo Finansów, Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/); dostęp 23.11.2026.
- [Ministerstwo Finansów, „Tryb offline24”](https://ksef.podatki.gov.pl/informacje-ogolne-ksef-20/tryb-offline24/); dostęp 4.11.2026.
- [Ministerstwo Finansów, „Tryb offline – niedostępność KSeF”](https://ksef.podatki.gov.pl/informacje-ogolne-ksef-20/tryb-offline-niedostepnosc-ksef/); dostęp 4.11.2026.
