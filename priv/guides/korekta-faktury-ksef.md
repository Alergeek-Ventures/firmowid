---
title: "Korekta faktury w KSeF: jak wystawić i czego nie zmienisz"
description: "Faktury z numerem KSeF nie da się edytować ani anulować. Błąd poprawia faktura korygująca sprzedawcy, a zły NIP nabywcy korekta do zera i nowa faktura."
published: 2026-11-12
updated: 2026-11-23
category: ksef-w-praktyce
---


Od chwili, gdy KSeF nada fakturze numer, dokumentu nie da się już w systemie zmienić ani usunąć, a każdą pomyłkę poprawia się fakturą korygującą wystawianą przez sprzedawcę. Ministerstwo Finansów przypomina w odpowiedziach na pytania podatników, że w okresie obowiązkowego KSeF nabywca nie wystawia już not korygujących, więc także błąd w danych nabywcy zauważony przez klienta poprawia wystawca. Liczba korekt do jednej faktury nie jest przy tym ograniczona, a system pozwala skorygować również fakturę z poprzedniego roku.

## Odrzucony plik i błędny NIP

Inaczej traktuje się plik XML, który KSeF odrzucił, ponieważ według MF taka faktura w ogóle nie została wystawiona i zamiast korekty wysyła się nowy, poprawny plik. Faktura z trybu offline już istnieje, dlatego po odrzuceniu wysyła się korektę techniczną, czyli tę samą fakturę w pliku zgodnym ze schematem. System nie sprawdza natomiast danych kontrahenta, więc faktura z błędnym NIP nabywcy zostaje przyjęta, a resort zaleca w takiej sytuacji korektę do zera dla niewłaściwego kontrahenta i nową fakturę dla właściwego. Korekty do zera nie wystawia się jednak na żądanie klienta tylko dlatego, że na fakturze zabrakło danych nieobowiązkowych albo podano je w innym formacie.

## Korekta kilku faktur naraz

Faktura korygująca zbiorcza musi wskazywać wszystkie faktury pierwotne, których dotyczy, czyli ich numery nadane przez sprzedawcę, numery KSeF i daty wystawienia. W Firmowidzie, naszym [programie do KSeF](/ksef), korekta pojawia się na stronie faktury pierwotnej, ma pole na przyczynę korekty i zestawienie pozycji przed korektą i po niej, a przypadkom, w których błąd powtarza się na kilkuset fakturach, poświęciliśmy osobny tekst o [masowej korekcie](/poradnik/masowa-korekta-faktur-ksef). Jeśli chcesz to sprawdzić na własnych fakturach, [zarejestruj](/zarejestruj) firmę i przez 60 dni korzystaj z wybranego planu za darmo.

## Czy fakturę wysłaną do KSeF można anulować?

Nie. Podręcznik KSeF 2.0 mówi o tym wprost: „W KSeF nie jest możliwe anulowanie wystawionej faktury”. Faktura z numerem KSeF weszła do obrotu prawnego i zostaje w systemie przez 10 lat od końca roku, w którym ją wystawiono. Usunąć jej też się nie da, bo według MF „Podatnicy nie mają możliwości samodzielnego usunięcia wystawionej faktury z systemu, niezależnie czy faktura była wystawiona prawidłowo czy nieprawidłowo”.

To, co programy nazywają anulowaniem, jest w praktyce korektą do zera.

## Czy do faktury z KSeF można wystawić notę korygującą?

Nie można. W podręczniku czytamy: „Od 1 lutego 2026 r. nie funkcjonują już również noty korygujące”. Nabywca, który zauważy błąd w swoich danych, zgłasza go sprzedawcy i czeka na jego fakturę korygującą.

## Co musi zawierać faktura korygująca w KSeF?

| Element | Uwagi z podręcznika MF |
|---|---|
| Numer kolejny i data wystawienia korekty | zawsze |
| Numer KSeF faktury pierwotnej | zawsze, poza fakturami, którym numeru KSeF nie nadano |
| Dane faktury pierwotnej | data wystawienia, numer nadany przez sprzedawcę, dane stron |
| Nazwa towaru lub usługi objętych korektą | poza korektą zbiorczą obejmującą wszystkie dostawy z danego okresu |
| Kwota korekty podstawy opodatkowania i podatku | gdy korekta zmienia kwoty |
| Prawidłowa treść korygowanych pozycji | w pozostałych przypadkach |
| Przyczyna korekty | „obecnie podawanie przyczyny korekty nie jest obowiązkowe” |

Numer KSeF faktury pierwotnej podaje się także wtedy, gdy była ona wystawiona w trybie offline24, przy niedostępności systemu albo w trybie awaryjnym.

## Czy w KSeF można wystawić korektę do korekty?

Kolejna korekta zawsze wskazuje fakturę pierwotną, a nie poprzednią korektę. Podręcznik zaznacza, że „W fakturze korygującej nie jest konieczne podawanie danych (numerów, dat wystawienia) wcześniej wystawionych faktur korygujących”. Kwoty liczy się natomiast od stanu po wcześniejszych korektach.

MF pokazuje to na liczbach. Faktura na 1000 zł netto, pierwsza korekta na -100 zł, bo miało być 900 zł. Po czasie okazuje się, że prawidłowa kwota to 700 zł, więc druga korekta opiewa na -200 zł netto i -46 zł VAT, a nie na -300 zł.

## Jak w KSeF skorygować dane nabywcy?

Nazwę i adres nabywcy poprawia zwykła faktura korygująca, w której dane sprzed korekty trafiają do sekcji Podmiot2K. Inaczej jest z numerem NIP. Podręcznik stwierdza: „Korekcie nie podlegają błędne numery identyfikujące nabywcę oraz dodatkowego nabywcę”, i to dlatego przy złym NIP zostaje korekta do zera i nowa faktura.

| Co jest błędne | Jak poprawić |
|---|---|
| Nazwa albo adres nabywcy | faktura korygująca dane nabywcy |
| NIP nabywcy | korekta do zera i nowa faktura z poprawnym NIP |
| Brak danych nieobowiązkowych, np. odbiorcy | według MF nie jest to powód do korekty do zera |
| Adres sprzedawcy | faktura korygująca, dane sprzed korekty w sekcji Podmiot1K |

## Jak skorygować w KSeF błędny numer faktury?

Fakturą korygującą. Struktura FA(3) ma na to osobne pole NrFaKorygowany, w którym podaje się poprawny numer, a błędny zostaje w danych faktury korygowanej. Sama kolejność wysyłki nie jest powodem do korekty: jeśli faktura o wcześniejszym numerze trafiła do KSeF później niż faktura o numerze późniejszym, to według podręcznika nie zobowiązuje to podatnika do poprawiania numeru.

## Jak w KSeF skorygować datę sprzedaży?

Także korektą, z prawidłową datą w treści. Na forach przedsiębiorcy pytają potem, dlaczego faktura dalej jest w raporcie za stary miesiąc. Struktura ma nieobowiązkowe pole TypKorekty z trzema wartościami: korekta skutkująca w dacie ujęcia faktury pierwotnej, w dacie wystawienia korekty albo w innej dacie. To, w którym okresie ująć korektę w ewidencji i w JPK, wynika z przepisów o VAT, nie z KSeF, więc najlepiej ustalić to z biurem księgowym przed wysłaniem.

Błędów rachunkowych system nie wychwyci. MF pisze o źle policzonej kwocie: „System nie weryfikuje takich błędów i przyjmie taki plik XML”. Faktura jest wtedy wystawiona z błędem i również wymaga korekty.

## Korekta w Firmowidzie

| Co chcesz zmienić | W Firmowidzie |
|---|---|
| Pozycje: ilość, cena, stawka VAT, nazwa | korekta ze stanem przed i po |
| Nazwa i adres nabywcy | korekta |
| Data sprzedaży, termin i forma płatności | korekta |
| NIP nabywcy | anulowanie i nowa faktura |
| Dane sprzedawcy | nie |
| Kilka faktur jedną korektą zbiorczą | nie |

Przycisk „Anuluj” wystawia korektę zerującą pozycje. W oknie potwierdzenia jest zdanie: „Wystawimy fakturę korygującą zerującą pozycje”. Przy próbie usunięcia faktury z numerem KSeF program odpowiada: „Nie można usunąć faktury wysłanej do KSeF. Wystaw fakturę korygującą”.

![Faktury z numerem KSeF nie da się zmienić, więc pomyłkę poprawia sprzedawca fakturą korygującą, a nabywca nie wystawia noty. Odrzucony plik wysyła się ponownie bez korekty. Przy błędnym NIP nabywcy wystawia się korektę do zera i nową fakturę.](/images/guides/korekta-faktury-ksef-kiedy.webp)

## Źródła

- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/) (wersja z 10.11.2026), dostęp 23.11.2026.
- [MF: Podręcznik KSeF 2.0, cz. II, rozdziały 1.6, 2.13 i 4.1.3](https://ksef.podatki.gov.pl/media/rronoxyt/podrecznik-ksef-20-cz-ii-wystawianie-i-otrzymywanie-faktur-w-ksef-06082026.pdf) (wersja z sierpnia 2026 r.), dostęp 23.11.2026.

*To informacja ogólna, nie porada podatkowa.*
