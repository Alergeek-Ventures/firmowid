---
title: "Certyfikat KSeF: jak pobrać, typ 1 i 2, ważność"
description: "Certyfikat KSeF pobiera się w Aplikacji Podatnika KSeF 2.0. Typ 1 loguje program do systemu, typ 2 podpisuje faktury offline, oba są ważne do 2 lat."
published: 2026-11-12
updated: 2026-11-23
category: ksef-w-praktyce
---

Certyfikaty KSeF są dwa. Typ 1 służy do logowania, typ 2 do drugiego kodu QR z napisem „CERTYFIKAT” na fakturze offline. O oba wnioskuje się w Aplikacji Podatnika KSeF 2.0 i oba są ważne najwyżej 2 lata.

| | Certyfikat typu 1 | Certyfikat typu 2 | Token |
|---|---|---|---|
| Do czego | logowanie do KSeF przez program | drugi kod QR na fakturze offline wręczanej przed wysłaniem do KSeF | logowanie programu do KSeF |
| Gdzie powstaje | Aplikacja Podatnika KSeF 2.0 albo program połączony z API | Aplikacja Podatnika KSeF 2.0 albo program połączony z API | Aplikacja Podatnika KSeF 2.0 albo program połączony z API |
| Ważność | do 2 lat | do 2 lat | do unieważnienia; rozporządzenie pozwala logować się tokenem do 31.12.2026 r., projekt nowelizacji wydłuża ten termin |
| Zawiera uprawnienia | nie | nie | tak, wybrane przy generowaniu |
| Działa dla kilku firm | tak | tak | nie |
| Można przekazać biuru księgowemu | nie, biuru księgowemu nadaje się uprawnienia | nie | nie, tokenem posługuje się ten, kto go wygenerował |

## Kto może wygenerować certyfikat KSeF?

Według podręcznika KSeF 2.0 certyfikat dostaje osoba fizyczna identyfikowana numerem NIP, czyli na przykład właściciel jednoosobowej działalności, albo numerem PESEL, czyli na przykład pracownik, o ile ma w KSeF jakiekolwiek uprawnienie. Spółka z o.o. i inny podmiot, który nie jest osobą fizyczną, występuje o certyfikat po zalogowaniu pieczęcią kwalifikowaną. Wtedy na fakturze wystawionej przez pracownika widać w systemie dane spółki, a nie jego nazwisko.

O certyfikat z danymi osoby fizycznej może wnioskować tylko ta osoba i tylko ona może go pobrać.

## Jak uzyskać certyfikat KSeF dla JDG?

Od listopada 2025 r. do końca stycznia 2026 r. wnioski przyjmował Moduł Certyfikatów i Uprawnień (MCU). Od lutego 2026 r. wnioskowanie i pobieranie działa w Aplikacji Podatnika KSeF 2.0 oraz przez API, z którego korzystają programy do faktur. Przedsiębiorca loguje się tam Profilem Zaufanym albo podpisem kwalifikowanym i składa wniosek z danymi zgodnymi z tymi, którymi się zalogował. We wniosku można wskazać dzień, od którego certyfikat ma być ważny. MF pokazuje te ekrany w instrukcji wideo „Składanie wniosku o certyfikat i zarządzanie certyfikatami” na stronie aplikacji.

Samym certyfikatem do Aplikacji Podatnika zalogować się nie da. Ministerstwo zaznacza, że działa on w programach komercyjnych połączonych z API KSeF 2.0.

## Ile ważny jest certyfikat w KSeF?

Nie dłużej niż 2 lata. Okres liczy się od daty wskazanej we wniosku, a gdy jej nie podano, od dnia wydania certyfikatu. MF podaje przykład: wniosek z 10 listopada 2025 r. z datą początkową 1 lutego 2026 r. daje certyfikat ważny przez 2 lata od 1 lutego. Przed tą datą nie da się nim uwierzytelnić.

Kolejny certyfikat „na zapas” system wyda najwcześniej na miesiąc przed końcem ważności najstarszego aktywnego.

## Ile certyfikatów KSeF można mieć?

| Na kogo wydany | Aktywne | Nowe, do użycia po wygaśnięciu obecnych | Wnioski w ciągu 30 dni |
|---|---|---|---|
| PESEL osoby fizycznej | 6 | 6 | 12 |
| NIP osoby fizycznej | 100 | 100 | 300 |
| NIP spółki lub innego podmiotu | 100 | 100 | 300 |
| Podpis lub pieczęć bez NIP i PESEL | 6 | 6 | 12 |

Limit wniosków liczy się niezależnie od unieważnień. W przykładzie z podręcznika pracownik dwanaście razy pobrał i unieważnił certyfikat w dwa tygodnie, a przy trzynastej próbie system odmówił do końca okresu 30 dni.

## Czy certyfikat KSeF jest obowiązkowy?

Ministerstwo nie wymaga certyfikatu od każdego podatnika, a w podręczniku nazywa typ 1 jedną z dopuszczalnych metod uwierzytelnienia, obok Węzła krajowego, podpisu kwalifikowanego, pieczęci i tokenu. W bezpłatnych narzędziach MF, w tym w Aplikacji Podatnika, certyfikatem zalogować się nie można, więc przedsiębiorca, który wystawia tam faktury po zalogowaniu Profilem Zaufanym, typu 1 nie używa wcale.

| Sposób pracy | Typ 1 | Typ 2 |
|---|---|---|
| Aplikacja Podatnika KSeF 2.0, logowanie Profilem Zaufanym | nie | nie |
| Program do faktur połączony tokenem | nie | tylko dla faktur offline |
| Program do faktur połączony certyfikatem | tak | tylko dla faktur offline |
| Faktury w trybie offline24, przy niedostępności i awarii KSeF | - | tak |

Typem 2 oznacza się fakturę offline kodem, który według MF pozwala nabywcy potwierdzić tożsamość wystawcy, gdy dostaje on dokument poza systemem. Same tryby opisuje tekst [tryb offline w KSeF](/poradnik/tryb-offline-ksef).

## Czy certyfikat KSeF jest nośnikiem uprawnień?

W rozdziale 2.5.9 podręcznika MF pisze: „Certyfikaty KSeF nie są natomiast nośnikiem uprawnień”, a typ 1 stanowi wyłącznie środek uwierzytelnienia, podobnie jak podpis kwalifikowany. Po zalogowaniu brane są pod uwagę uprawnienia powiązane z NIP-em lub PESEL-em zapisanym w certyfikacie, przy czym system uwzględnia powiązanie obu identyfikatorów tej samej osoby.

Podręcznik pokazuje to na przykładzie: „Księgowa Anna Nowak (NIP 9999999999) prowadząca jednoosobową działalność gospodarczą dysponuje certyfikatem KSeF typu 1”, a uprawnienia nadały jej firmy X, Y i Z. Dalej MF pisze: „Jeżeli po określonym czasie firma Z odbierze Annie Nowak uprawnienia, to posiadany przez nią certyfikat KSeF nie ulegnie unieważnieniu”. Nowy klient też nie wymaga nowego certyfikatu, wystarczy, że nada uprawnienia.

O tokenie ten sam rozdział mówi, że „zawiera w sobie uprawnienia podatnika, które są deklarowane w momencie jego generowania”.

## Czy certyfikat KSeF można unieważnić?

Można, i robi to wyłącznie właściciel. W podręczniku czytamy: „Nie jest możliwe wykonywanie jakichkolwiek operacji na certyfikatach należących do innych osób fizycznych lub podmiotów”. Żądanie unieważnienia wymaga uwierzytelnienia jedną z metod: Węzeł krajowy, podpis kwalifikowany, pieczęć kwalifikowana albo certyfikat KSeF. Jeżeli unieważniany jest certyfikat typu 1, którym ktoś jest w tej chwili zalogowany, następuje przerwanie sesji.

Na liście swoich certyfikatów użytkownik widzi numer seryjny, nazwę własną, typ, status oraz okres ważności. Statusy są cztery: A (aktywny), Z (zablokowany), U (unieważniony) i W (wygasły).

## Do kiedy działają tokeny KSeF?

Obowiązujące rozporządzenie z 12 grudnia 2025 r. (Dz.U. poz. 1815) pozwala uwierzytelniać się tokenem do 31 grudnia 2026 r. Ministerstwo Finansów ogłosiło jednak, że utrzyma tokeny bezterminowo, a 27 października 2026 r. na stronach Rządowego Centrum Legislacji pojawił się projekt nowelizacji. Zakłada on, że tokeny wytworzone przed 1 stycznia 2027 r. będą działać do 30 listopada 2027 r., a nowe najwyżej 365 dni.

W dniu aktualizacji tego tekstu nie znaleźliśmy ogłoszenia nowelizacji w Dzienniku Ustaw. Kto łączy program z KSeF tokenem, powinien przed końcem grudnia sprawdzić, czy zmiana weszła w życie, albo przejść na certyfikat typu 1.

## Dlaczego token KSeF nie działa?

| Objaw | Przyczyna |
|---|---|
| Program odrzuca token wygenerowany w KSeF 1.0 | według MF tokeny z KSeF 1.0 nie są zgodne z KSeF 2.0, trzeba wygenerować nowy |
| Tokenu nie da się odczytać ponownie | Aplikacja Podatnika pokazuje go tylko raz, zaraz po wygenerowaniu |
| Token loguje, ale wysyłka faktury jest odrzucana | token ma tylko te uprawnienia, które wybrano przy generowaniu |
| Token jednej firmy nie działa w drugiej | tokenu nie da się użyć w różnych kontekstach |
| Nie da się nim zalogować do Aplikacji Podatnika | aplikacja MF nie przyjmuje tokenów |
| Token nie mieści się w polu programu na 64 znaki | zgłoszenia z forów: token z KSeF 2.0 jest dłuższy, potrzebna wersja programu obsługująca KSeF 2.0 |

## Certyfikat a biuro księgowe i bank

| Sytuacja | Co działa |
|---|---|
| Biuro księgowe ma wystawiać faktury za firmę | uprawnienia nadane przez właściciela, nie jego certyfikat |
| Moduł KSeF w banku, np. Księgowość z Żubrem w Pekao | certyfikat pobrany z aplikacji MF i wgrany w banku |
| Faktura offline wręczana klientowi przed wysłaniem | certyfikat typu 2 wygenerowany wcześniej |

Według MF certyfikat jest osobistym poświadczeniem tożsamości. Nie pożycza się go. O nadawaniu uprawnień jest osobny tekst: [dostęp do KSeF w JDG i dla biura księgowego](/poradnik/dostep-do-ksef-jdg-i-ksiegowa).

## Certyfikat w Firmowidzie

[Firmowid](/ksef), nasz program, przyjmuje token albo certyfikat. Przy certyfikacie zapisuje datę wygaśnięcia.

Najprościej połączyć go Profilem Zaufanym, bo wtedy Firmowid sam zamawia certyfikat w KSeF. Kto ma już własny certyfikat typu 1, wgrywa dwa pliki, `.crt` i `.key`, i podaje hasło do klucza prywatnego. Przy tokenie w ustawieniach widać ostrzeżenie: „Tokeny KSeF będą obsługiwane tylko do 1 stycznia 2027 roku. Zalecamy uwierzytelnienie Profilem Zaufanym lub certyfikatem KSeF”.

Faktur offline u nas nie ma, więc typ 2 się nie przyda. Zrzuty ekranu każdego kroku: [jak połączyć Firmowid z KSeF](/pomoc/polaczenie-z-ksef).

![Certyfikat typu 1 służy do logowania do KSeF, certyfikat typu 2 do drugiego kodu QR z napisem CERTYFIKAT na fakturze offline, a token do logowania programu; rozporządzenie pozwala logować się nim do 31 grudnia 2026 r. Certyfikatu nie przekazuje się biuru księgowemu, tylko nadaje mu uprawnienia.](/images/guides/certyfikat-ksef-typ-1-typ-2-token.webp)

## Źródła

- [MF: Podręcznik KSeF 2.0, cz. I, rozdziały 2.4 i 2.5](https://ksef.podatki.gov.pl/media/dmrfdixs/podrecznik-ksef-20-cz-i-rozpoczecie-korzystania-z-ksef-06082026.pdf) (wersja z sierpnia 2026 r.), dostęp 23.11.2026.
- [MF: Certyfikaty KSeF](https://ksef.podatki.gov.pl/informacje-ogolne-ksef-20/certyfikaty-ksef/), dostęp 23.11.2026.
- [MF: Aplikacja Podatnika KSeF 2.0](https://ksef.podatki.gov.pl/aplikacja-podatnika-ksef-20/), dostęp 23.11.2026.
- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/), dostęp 23.11.2026.
- Rozporządzenie Ministra Finansów i Gospodarki z 12 grudnia 2025 r. w sprawie korzystania z Krajowego Systemu e-Faktur (Dz.U. poz. 1815), § 13 ust. 1 pkt 1, oraz projekt jego nowelizacji z 26 października 2026 r. (nr 138/2026 w wykazie prac legislacyjnych MFiG), za: [Infor.pl](https://ksiegowosc.infor.pl/wiadomosci/7690858,zmiany-w-ksef-od-2027-r-certyfikaty-powiazane-z-nip-przedluzenie-waznosci-tokenow-identyfikatory-zbiorcze-do-oznaczania-platnosci-za-wiecej-niz-jedna-fakture-nowelizacja-rozporzadzenia-mf.html), dostęp 23.11.2026.
- [Bank Pekao: KSeF](https://www.pekao.com.pl/przedsiebiorcy/uslugi-dodatkowe/ksef.html), dostęp 10.11.2026.

*To informacja ogólna, nie porada podatkowa.*
