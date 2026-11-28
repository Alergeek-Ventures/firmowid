---
title: "Jak połączyć Firmowid z KSeF: krok po kroku"
description: "Połączenie Firmowida z KSeF Profilem Zaufanym, certyfikatem albo tokenem, ze zrzutem ekranu przy każdym kroku. Trwa kilka minut."
published: 2026-11-18
updated: 2026-11-18
category: faktury-i-ksef
---

Połączenie robi się raz, w ustawieniach firmy, i zajmuje kilka minut. Masz trzy sposoby: Profil Zaufany, własny certyfikat KSeF albo token. Jeśli nie masz jeszcze certyfikatu, wybierz Profil Zaufany, bo wtedy certyfikat powstaje sam.

**Co trzeba mieć:** rolę administratora w Firmowidzie i dostęp do KSeF dla NIP-u firmy. W jednoosobowej działalności masz go z urzędu; w spółce zależy od uprawnień ([dostęp do KSeF w JDG i dla biura księgowego](/poradnik/dostep-do-ksef-jdg-i-ksiegowa)).

## Krok 1. Otwórz ustawienia KSeF

W pasku bocznym, w sekcji „Firma”, kliknij **KSeF**. Status pokaże „Niepołączono z KSeF”, a pod nim trzy zakładki z metodami.

![Pasek boczny z pozycją KSeF i formularz łączenia z trzema zakładkami](/images/guides/pomoc/ksef-1-ustawienia.webp)

## Sposób A: Profil Zaufany (polecany)

**Krok 2.** Na zakładce „Profil Zaufany” kliknij **Pobierz wniosek**. Na dysk trafi plik `wniosek.xml` z NIP-em Twojej firmy.

![Krok „Pobierz wniosek”](/images/guides/pomoc/ksef-2-pobierz-wniosek.webp)

**Krok 3.** Kliknij link **Profilem Zaufanym**. Otworzy się podpis.gov.pl. Wgraj tam pobrany plik i podpisz go Profilem Zaufanym (podpis kwalifikowany też zadziała). Zapisz podpisany plik.

![Link do podpisu na podpis.gov.pl](/images/guides/pomoc/ksef-3-podpisz.webp)

**Krok 4.** Wróć do Firmowida, kliknij **Dodaj podpisany plik (.xml)**, wskaż podpisany plik i kliknij **Wyślij plik**.

![Pole na podpisany plik i przycisk „Wyślij plik”](/images/guides/pomoc/ksef-4-wgraj.webp)

Resztę Firmowid robi sam: loguje się do KSeF Twoim podpisem, zamawia certyfikat i go odbiera. W tym czasie zobaczysz kolejno „Trwa uwierzytelnianie w KSeF.”, „Trwa przygotowanie wniosku o certyfikat.” i „KSeF wystawia certyfikat.”.

## Sposób B: własny certyfikat KSeF

Na zakładce **Certyfikat KSeF**: wygeneruj w aplikacji KSeF certyfikat o przeznaczeniu „Uwierzytelnienie w systemie KSeF”, dodaj dwa pliki (`.crt` i `.key`), wpisz hasło do klucza prywatnego i kliknij **Wyślij certyfikat**. Pliki muszą być w formacie tekstowym (PEM). Różnice między typami certyfikatów: [certyfikat KSeF typu 1 i 2](/poradnik/certyfikat-ksef-typ-1-i-2).

![Zakładka „Certyfikat KSeF”](/images/guides/pomoc/ksef-5a-certyfikat.webp)

## Sposób C: token (tylko do 1 stycznia 2027 r.)

Na zakładce **Token**: wygeneruj w aplikacji KSeF token z uprawnieniami do wystawiania i przeglądania faktur, wklej go i kliknij **Połącz z KSeF**. Firmowid sprawdzi, czy NIP w tokenie zgadza się z NIP-em firmy. Obecne przepisy pozwalają używać tokenów do końca 2026 r., a projekt nowelizacji wydłuża działanie już wydanych tokenów do 30 listopada 2027 r. Firmowid traktuje na razie połączenie tokenem jako ważne do 1 stycznia 2027 r., więc przed tą datą najlepiej przełączyć się na Profil Zaufany albo certyfikat.

![Zakładka „Token” z ostrzeżeniem o wygaszaniu metody](/images/guides/pomoc/ksef-5b-token.webp)

## Krok 5. Sprawdź, czy działa

Status zmieni się na **Połączono z KSeF**, obok zobaczysz typ autoryzacji i datę wygaśnięcia. Od tej chwili możesz wystawiać faktury, a Firmowid pobiera z KSeF faktury z ostatnich 30 dni i potem co 2 godziny ([Pobieranie faktur z KSeF](/pomoc/pobieranie-faktur-z-ksef)).

![Status „Połączono z KSeF”, typ autoryzacji i data wygaśnięcia](/images/guides/pomoc/ksef-6-polaczono.webp)

## Odnowienie i rozłączenie

- Certyfikat, któremu zostało mniej niż 30 dni, Firmowid odnawia sam w nocy. Token się nie odnawia.
- Gdy połączenie wygaśnie, w Skrzynce, w grupie „Pilne”, pojawi się „Połączenie z KSeF wygasło”. Do czasu ponownego połączenia fakturę zapiszesz tylko jako wersję roboczą.
- **Rozłącz** usuwa zapisane dane dostępowe i zatrzymuje pobieranie faktur. Faktury pobrane wcześniej zostają.

Firmowid wysyła faktury tylko przy działającym połączeniu; trybu offline nie obsługuje ([tryb offline w KSeF](/poradnik/tryb-offline-ksef)).

Zobacz też: [Faktury z wysyłką do KSeF](/ksef) · [Pierwsza faktura w KSeF krok po kroku](/poradnik/pierwsza-faktura-ksef)
