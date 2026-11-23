---
title: "Certyfikat KSeF: typ 1, typ 2 i token"
description: "Do czego służy certyfikat KSeF typu 1 i typu 2, czym różni się od tokenu, gdzie go wygenerować i dlaczego nie przekazuje się go biuru księgowemu."
published: 2026-11-12
updated: 2026-11-23
category: ksef-w-praktyce
---

Certyfikaty KSeF są dwa. Typ 1 służy do logowania, typ 2 do drugiego kodu QR z napisem „CERTYFIKAT” na fakturze offline.

| | Certyfikat typu 1 | Certyfikat typu 2 | Token |
|---|---|---|---|
| Do czego | logowanie do KSeF, także przez program | drugi kod QR na fakturze offline wręczanej przed wysłaniem do KSeF | logowanie programu do KSeF |
| Gdzie powstaje | aplikacja MF (moduł certyfikatów) | aplikacja MF (moduł certyfikatów) | Aplikacja Podatnika KSeF |
| Ważność | do daty wygaśnięcia | do daty wygaśnięcia | do unieważnienia, ale rozporządzenie pozwala logować się tokenem do 31.12.2026 r., a MF zapowiada przedłużenie |
| Można przekazać biuru księgowemu | nie, biuru księgowemu nadaje się uprawnienia | nie | brak informacji w odpowiedziach MF |

## Jak wygenerować certyfikat

Certyfikat bierze się z modułu certyfikatów w aplikacji MF. Logowanie jak do KSeF, profilem zaufanym, mObywatelem albo podpisem. Potem nazwa (dowolna, np. „laptop biuro”), typ i pobranie dwóch plików: certyfikatu i klucza prywatnego na hasło. Hasło zapisz od razu, gdzieś poza tym laptopem. Ministerstwo go nie zna i nie przypomni.

## Przykład z fakturą offline

Hydraulik, piwnica, zero zasięgu, a klient chce fakturę teraz. Faktura z trybu offline ma wtedy dwa kody QR. Jeden prowadzi do danych faktury. Drugi, podpisany „CERTYFIKAT”, mówi, kto ją wystawił, i da się go zrobić tylko certyfikatem typu 2 ściągniętym wcześniej, jeszcze w biurze. Do KSeF faktura musi trafić najpóźniej następnego dnia roboczego ([tryb offline](/poradnik/tryb-offline-ksef)).

## Token czy certyfikat

Token to droga na skróty. Generujesz go w Aplikacji Podatnika i wklejasz w program, koniec. Haczyk jest jeden: rozporządzenie pozwala się nim logować do 31 grudnia 2026 r. MF obiecuje przedłużenie, ale daty jeszcze nie ma, więc kto podłącza program dziś, tokenem zrobi to szybciej, a certyfikatem oszczędzi sobie nerwów w styczniu.

## Kiedy certyfikat przestaje działać

Certyfikat ma datę ważności i po niej program po prostu przestaje się łączyć z KSeF. Wtedy generuje się nowy i wgrywa go w programie. Można go też unieważnić wcześniej, choćby wtedy, gdy ktoś ukradł laptopa razem z plikiem i zapisanym hasłem.

## Na co uważać

| Sytuacja | Co działa |
|---|---|
| Biuro księgowe ma wystawiać faktury za firmę | uprawnienia nadane przez właściciela, nie jego certyfikat |
| Token wygenerowany w KSeF 1.0 | nie działa w KSeF 2.0, trzeba wygenerować nowy |
| Moduł KSeF w banku, np. Księgowość z Żubrem w Pekao | certyfikat pobrany z aplikacji MF i wgrany w banku |
| Faktura offline wręczana klientowi przed wysłaniem | certyfikat typu 2 wygenerowany wcześniej |

Według MF certyfikat jest osobistym poświadczeniem tożsamości. Nie pożycza się go.

[Firmowid](/pomoc/polaczenie-z-ksef), nasz program, przyjmuje token albo certyfikat. Przy certyfikacie zapisuje datę wygaśnięcia.

![Certyfikat typu 1 służy do logowania do KSeF, certyfikat typu 2 do drugiego kodu QR z napisem CERTYFIKAT na fakturze offline, a token do logowania programu; rozporządzenie pozwala logować się nim do 31 grudnia 2026 r. Certyfikatu nie przekazuje się biuru księgowemu, tylko nadaje mu uprawnienia.](/images/guides/certyfikat-ksef-typ-1-typ-2-token.webp)

## Źródła

- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/), dostęp 11.11.2026.
- [PKO Bank Polski: Faktury elektroniczne KSeF](https://www.pkobp.pl/firmy/uslugi-dla-firm/e-ksiegowosc/faktury-elektroniczne), dostęp 10.11.2026 (moduł certyfikatów MF).
- [Bank Pekao: KSeF](https://www.pekao.com.pl/przedsiebiorcy/uslugi-dodatkowe/ksef.html), dostęp 10.11.2026.
- Uprawnienia dla biura księgowego: [dostęp do KSeF w JDG](/poradnik/dostep-do-ksef-jdg-i-ksiegowa).
