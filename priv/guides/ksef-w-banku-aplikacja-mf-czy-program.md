---
title: "KSeF w banku, aplikacja Ministerstwa Finansów czy program do faktur?"
description: "Bezpłatne narzędzia MF, moduł KSeF w banku i osobny program do faktur: co potrafi każde z nich i komu wystarczy przy kilku fakturach w miesiącu."
published: 2026-11-12
updated: 2026-11-23
category: wybor-programu
---

Ministerstwo Finansów udostępnia do KSeF Aplikację Podatnika w przeglądarce, e-mikrofirmę w e-Urzędzie Skarbowym oraz, od 1 lutego 2026 r., aplikację mobilną, ale żadne z tych narzędzi nie ma wglądu w konto firmowe, przez co wpłat od klientów pilnuje się w bankowości.

## Porównanie

| Rozwiązanie | Faktury w KSeF | Cena | Połączenie z KSeF | Wpłaty od klientów |
|---|---|---|---|---|
| **Aplikacja Podatnika KSeF (MF)** | wystawianie, odbiór, UPO, uprawnienia | bezpłatna | login.gov.pl, podpis albo pieczęć kwalifikowana | nie |
| **Aplikacja mobilna KSeF (MF)** | wystawianie faktur i korekt, tryb offline | bezpłatna | mObywatel, mojeID, e-dowód albo profil zaufany | nie |
| **e-mikrofirma (MF)** | wystawianie, odbiór, przeniesienie do ewidencji VAT | bezpłatna | login.gov.pl albo mObywatel | nie |
| **Pekao, Księgowość z Żubrem** | wystawianie, wysyłka i pobieranie | pakiet Self Service w promocji za 0 zł nawet do 24 mies. | certyfikat KSeF z portalu MF | automatyczne rozliczanie wpłat na rachunek w Pekao, zależnie od pakietu |
| **PKO BP, e-Księgowość** | zapowiedź: pobieranie, wystawianie i przesyłanie | brak na stronie | certyfikat KSeF | brak informacji |
| **Firmowid, plan Darmowy** | wysyłka i pobieranie bez limitu | 0 zł | token albo certyfikat KSeF | 1 konto przez Open Banking z automatycznym dopasowaniem przelewów |

## Czy trzeba kupować program do KSeF?

Za samo wystawianie i odbieranie faktur w KSeF nie trzeba płacić ani złotówki, bo [Aplikacja Podatnika KSeF](https://ksef.podatki.gov.pl/aplikacja-podatnika-ksef-20/), aplikacja mobilna i e-mikrofirma są bezpłatne, a ministerstwo nie publikuje w nich limitu dokumentów.

| Potrzeba | Narzędzia MF | Program do faktur |
|---|---|---|
| Wystawianie i odbiór faktur w KSeF | tak | tak |
| UPO, uprawnienia, korekty | tak | zwykle tak |
| Tryb offline24 i kody QR | aplikacja mobilna, z certyfikatem KSeF typu 2 | zależy od programu |
| Przeniesienie faktur do ewidencji VAT | e-mikrofirma | w programach z księgowością |
| Informacja, kto zapłacił | nie | w programach połączonych z bankiem |
| Kilka osób wystawiających faktury | uprawnienia nadawane w Aplikacji Podatnika | osobne konta użytkowników |
| Cena | 0 zł | plan za 0 zł z limitem, bez limitu albo abonament |

![Narzędzia Ministerstwa Finansów i program do faktur w jednej tabeli. Wystawianie i odbiór faktur w KSeF działa w obu. UPO, uprawnienia i korekty są w narzędziach MF, w programach zwykle też. Tryb offline24 z kodami QR ma aplikacja mobilna z certyfikatem typu 2, w programach zależy to od programu. Do ewidencji VAT przenosi faktury e-mikrofirma albo program z księgowością. Informację, kto zapłacił, dają tylko programy połączone z bankiem. Narzędzia MF kosztują 0 zł, programy mają plan za 0 zł z limitem, bez limitu albo abonament.](/images/guides/czy-trzeba-kupowac-program-mf-czy-program.webp)

## Aplikacja mobilna KSeF

Aplikację Mobilną KSeF Ministerstwo Finansów udostępnia bezpłatnie od 1 lutego 2026 r. Łączy się tylko z produkcyjnym KSeF.

| Funkcja | W aplikacji mobilnej |
|---|---|
| Wystawianie faktur i korekt | tak |
| Kopie robocze faktur | tak |
| Zapisani nabywcy, rachunki bankowe i profile przedsiębiorcy | tak |
| Wyszukiwanie i pobieranie faktur wysłanych do KSeF | tak |
| Wystawianie bez internetu i w czasie niedostępności KSeF | tak, z wcześniej pobranym certyfikatem KSeF typu 2 |
| Podgląd szczegółów załącznika do faktury | nie |
| Wystawianie faktur z załącznikiem | nie, tylko programy zintegrowane z API |
| Wersja testowa do ćwiczeń | nie, tylko produkcyjna |

Logowanie idzie przez login.gov.pl: mObywatel, mojeID, e-dowód albo profil zaufany.

| Kto się loguje | Skąd ma uprawnienia w KSeF |
|---|---|
| Właściciel JDG | z automatu, po NIP powiązanym z PESEL |
| Pracownik firmy | nadaje je właściciel w Aplikacji Podatnika KSeF |
| Biuro rachunkowe | nadaje je właściciel na NIP biura |

Środowisko testowe działa tylko w przeglądarkowej Aplikacji Podatnika KSeF.

![Aplikacja Mobilna KSeF wystawia faktury i korekty, zapisuje kopie robocze, nabywców i rachunki, pobiera faktury z KSeF a bez internetu działa z wcześniej pobranym certyfikatem KSeF typu 2. Nie pokazuje szczegółów załącznika, nie wystawia faktur z załącznikiem i nie ma wersji testowej.](/images/guides/aplikacja-mobilna-ksef-co-potrafi.webp)

## Moduły KSeF w bankach

Strony dwóch dużych banków opisywały 10 listopada KSeF na zupełnie innym etapie. W Pekao24 można włączyć moduł Księgowość z Żubrem i po wgraniu certyfikatu pobranego z portalu ministerstwa wysyłać przez niego faktury do KSeF oraz odbierać te wystawione na firmę, a pakiet Self Service bank daje w promocji za 0 zł nawet przez 24 miesiące, nie pisząc, ile kosztuje potem. PKO BP na stronie serwisu e-Księgowość pisze z kolei w czasie przyszłym, że serwis zostanie dostosowany do KSeF, więc nie dało się z niej wyczytać, czy ta funkcja już działa. O tym, czy moduł bankowy widzi rachunki w innych bankach, żadna z tych stron nie wspomina.

## Program do faktur

Osobny program do faktur działa niezależnie od banku i bywa płatny, ale łączy KSeF z tym, czego brakuje narzędziom ministerstwa, czyli z przypomnieniami o płatnościach, kontami dla biura księgowego albo wspólnika czy dopasowaniem przelewów. U części producentów darmowy plan kończy się po trzech fakturach w miesiącu, jak w planie Micro Fakturowni, a w inFakcie najtańszy plan z KSeF kosztował na początku listopada 9,90 zł miesięcznie przy płatności rocznej. Nasz Firmowid w planie za 0 zł wysyła faktury do KSeF bez limitu, pobiera koszty i [dopasowuje przelewy](/funkcje/bank) z jednego konta podłączonego przez Open Banking, za to nie prowadzi księgowości. Przy dwóch fakturach w miesiącu i klientach, którzy płacą na czas, przesiadka z aplikacji ministerstwa na cokolwiek innego niewiele zmieni.

![Porównanie: Aplikacja Podatnika KSeF, aplikacja mobilna i e-mikrofirma są bezpłatne, ale nie widzą wpłat od klientów. Moduł Pekao jest w promocji za 0 zł do 24 miesięcy i zależnie od pakietu rozlicza wpłaty na rachunek w Pekao, PKO BP nie podaje ceny. Firmowid w planie Darmowym kosztuje 0 zł i dopasowuje wpłaty z jednego konta przez Open Banking.](/images/guides/ksef-bank-aplikacja-mf-program-porownanie.webp)

## Źródła

- [MF: Aplikacja Podatnika KSeF i inne narzędzia](https://ksef.podatki.gov.pl/aplikacja-podatnika-ksef-i-inne-narzedzia/), dostęp 10.11.2026.
- [MF: Aplikacja mobilna KSeF](https://ksef.podatki.gov.pl/aplikacja-podatnika-ksef-i-inne-narzedzia/aplikacja-mobilna-ksef/), dostęp 10.11.2026.
- [Bank Pekao: KSeF](https://www.pekao.com.pl/przedsiebiorcy/uslugi-dodatkowe/ksef.html), dostęp 10.11.2026.
- [PKO Bank Polski: Faktury elektroniczne KSeF](https://www.pkobp.pl/firmy/uslugi-dla-firm/e-ksiegowosc/faktury-elektroniczne), dostęp 10.11.2026.
- Fakturownia, plan Micro: cennik fakturownia.pl, stan 26.10.2026; inFakt: cennik infakt.pl, stan 3.11.2026.
- [MF: Jak uzyskać dostęp do KSeF](https://ksef.podatki.gov.pl/krok-po-kroku-jdg-i-msp/), dostęp 11.11.2026.
- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/), dostęp 11.11.2026.
- [Firmowid: cennik](https://firmowid.pl/cennik), dostęp 10.11.2026.
