---
title: "KSeF w banku, aplikacja Ministerstwa Finansów czy program do faktur?"
description: "Bezpłatne narzędzia MF, moduł KSeF w banku i osobny program do faktur: co potrafi każde z nich i komu wystarczy przy kilku fakturach w miesiącu."
published: 2026-11-12
updated: 2026-11-27
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

## Ile faktur można wystawić w KSeF za darmo?

Limitu nie ma w żadnym z opisów narzędzi ministerstwa. Na pytanie, czy trzeba mieć płatny program, MF odpowiada: „Nie. Ministerstwo Finansów zapewnia bezpłatne narzędzia”. Podręcznik KSeF 2.0 dodaje, że aplikacje te „mogą także stanowić docelowe narzędzie”, a nie tylko rozwiązanie na okres przejściowy.

## Czym się różni Aplikacja Podatnika KSeF od aplikacji mobilnej?

| Narzędzie | Gdzie działa | Do czego według MF |
|---|---|---|
| Aplikacja Podatnika KSeF | przeglądarka | faktury, uprawnienia, tokeny, certyfikaty, UPO |
| Aplikacja Mobilna KSeF | smartfon | wystawianie i odbieranie faktur, wersje robocze |
| e-mikrofirma | e-Urząd Skarbowy | faktury i ewidencja VAT |

Aplikacja Podatnika ma trzy wersje: testową od 3 listopada 2025 r., przedprodukcyjną od 15 listopada 2025 r. i produkcyjną od 1 lutego 2026 r. Fakturę da się w tych narzędziach także zapisać i wydrukować. Podręcznik: „E-Fakturę można pobrać (np. w postaci pliku pdf) także w bezpłatnych narzędziach oferowanych przez MF”.

## Czy e-mikrofirma jest powiązana z KSeF?

Tak. Na stronie ministerstwa: „Aplikacja e-mikrofirma została zintegrowana z KSeF”. Istniejące konto trzeba z KSeF powiązać, a potem faktury z systemu trafiają do ewidencji VAT „bez konieczności ręcznego przepisywania danych”.

| Pytanie | Odpowiedź MF |
|---|---|
| Gdzie jest e-mikrofirma | w e-Urzędzie Skarbowym |
| Jak się zalogować | login.gov.pl albo mObywatel |
| Logowanie danymi podatkowymi | nie działa |
| Numery KSeF w JPK_VAT | ewidencja zasilana danymi faktur |

## Moduły KSeF w bankach

Strony dwóch dużych banków opisywały 10 listopada KSeF na zupełnie innym etapie. W Pekao24 można włączyć moduł Księgowość z Żubrem i po wgraniu certyfikatu pobranego z portalu ministerstwa wysyłać przez niego faktury do KSeF oraz odbierać te wystawione na firmę, a pakiet Self Service bank daje w promocji za 0 zł nawet przez 24 miesiące, nie pisząc, ile kosztuje potem. PKO BP na stronie serwisu e-Księgowość pisze z kolei w czasie przyszłym, że serwis zostanie dostosowany do KSeF, więc nie dało się z niej wyczytać, czy ta funkcja już działa. O tym, czy moduł bankowy widzi rachunki w innych bankach, żadna z tych stron nie wspomina.

## Czy do KSeF można zalogować się przez bankowość elektroniczną?

Można, ale to co innego niż moduł KSeF w banku. Bank potwierdza wtedy tylko tożsamość na login.gov.pl. MF wymienia tę drogę obok innych: „za pośrednictwem login.gov.pl wykorzystując m.in. aplikację mObywatel, bankowość elektroniczną, e-dowód lub Profil Zaufany”. Podręcznik przypomina, że „bezpłatną metodą logowania do KSeF dla osób fizycznych jest Węzeł krajowy”.

## Czy aplikacja KSeF wysyła powiadomienia?

O nowej fakturze kosztowej system sam nie zawiadomi. Podręcznik: „KSeF nie wysyła automatycznie powiadomień systemowych o otrzymaniu nowej faktury w systemie”. Dopuszcza za to powiadomienia „lokalnie, na poziomie poszczególnych programów finansowo-księgowych”. Sprzedawca też nie zobaczy, czy klient fakturę pobrał. Firmowid sprawdza KSeF co 2 godziny i sam pobiera nowe faktury kosztowe.

## Program do faktur

Osobny program do faktur działa niezależnie od banku i bywa płatny, ale łączy KSeF z tym, czego brakuje narzędziom ministerstwa, czyli z przypomnieniami o płatnościach, kontami dla biura księgowego albo wspólnika czy dopasowaniem przelewów. U części producentów darmowy plan kończy się po trzech fakturach w miesiącu, jak w planie Micro Fakturowni, a w inFakcie najtańszy plan z KSeF kosztował na początku listopada 9,90 zł miesięcznie przy płatności rocznej. Nasz Firmowid w planie za 0 zł wysyła faktury do KSeF bez limitu, pobiera koszty i [dopasowuje przelewy](/funkcje/bank) z jednego konta podłączonego przez Open Banking, za to nie prowadzi księgowości. Przy dwóch fakturach w miesiącu i klientach, którzy płacą na czas, przesiadka z aplikacji ministerstwa na cokolwiek innego niewiele zmieni.

![Porównanie: Aplikacja Podatnika KSeF, aplikacja mobilna i e-mikrofirma są bezpłatne, ale nie widzą wpłat od klientów. Moduł Pekao jest w promocji za 0 zł do 24 miesięcy i zależnie od pakietu rozlicza wpłaty na rachunek w Pekao, PKO BP nie podaje ceny. Firmowid w planie Darmowym kosztuje 0 zł i dopasowuje wpłaty z jednego konta przez Open Banking.](/images/guides/ksef-bank-aplikacja-mf-program-porownanie.webp)

## Źródła

- [MF: Aplikacja Podatnika KSeF i inne narzędzia](https://ksef.podatki.gov.pl/aplikacja-podatnika-ksef-i-inne-narzedzia/), dostęp 10.11.2026 i 23.11.2026.
- [MF: Aplikacja mobilna KSeF](https://ksef.podatki.gov.pl/aplikacja-podatnika-ksef-i-inne-narzedzia/aplikacja-mobilna-ksef/), dostęp 10.11.2026.
- [Bank Pekao: KSeF](https://www.pekao.com.pl/przedsiebiorcy/uslugi-dodatkowe/ksef.html), dostęp 10.11.2026.
- [PKO Bank Polski: Faktury elektroniczne KSeF](https://www.pkobp.pl/firmy/uslugi-dla-firm/e-ksiegowosc/faktury-elektroniczne), dostęp 10.11.2026.
- Fakturownia, plan Micro: cennik fakturownia.pl, stan 26.10.2026; inFakt: cennik infakt.pl, stan 3.11.2026.
- [MF: Jak uzyskać dostęp do KSeF](https://ksef.podatki.gov.pl/krok-po-kroku-jdg-i-msp/), dostęp 11.11.2026.
- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/), dostęp 11.11.2026 i 23.11.2026.
- [MF: Podręcznik KSeF 2.0, cz. I](https://ksef.podatki.gov.pl/media/dmrfdixs/podrecznik-ksef-20-cz-i-rozpoczecie-korzystania-z-ksef-06082026.pdf) i [cz. II, rozdziały 1.6.5, 3.1, 6.2, 6.4 i 6.5](https://ksef.podatki.gov.pl/media/rronoxyt/podrecznik-ksef-20-cz-ii-wystawianie-i-otrzymywanie-faktur-w-ksef-06082026.pdf) (wersje z sierpnia 2026 r.), dostęp 23.11.2026.
- [Firmowid: cennik](https://firmowid.pl/cennik), dostęp 10.11.2026.
