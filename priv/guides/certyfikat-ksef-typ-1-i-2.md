---
title: "Certyfikat KSeF: typ 1, typ 2 i token"
description: "Do czego służy certyfikat KSeF typu 1 i typu 2, czym różni się od tokenu, gdzie go wygenerować i dlaczego nie przekazuje się go księgowej."
published: 2026-11-12
updated: 2026-11-12
category: ksef-w-praktyce
---

Certyfikaty KSeF są dwa. Typ 1 służy do logowania, typ 2 do drugiego kodu QR z napisem „CERTYFIKAT” na fakturze offline.

| | Certyfikat typu 1 | Certyfikat typu 2 | Token |
|---|---|---|---|
| Do czego | logowanie do KSeF, także przez program | drugi kod QR na fakturze offline wręczanej przed wysłaniem do KSeF | logowanie programu do KSeF |
| Gdzie powstaje | aplikacja MF (moduł certyfikatów) | aplikacja MF (moduł certyfikatów) | Aplikacja Podatnika KSeF |
| Ważność | do daty wygaśnięcia | do daty wygaśnięcia | do unieważnienia przez użytkownika |
| Można przekazać księgowej | nie, księgowej nadaje się uprawnienia | nie | brak informacji w odpowiedziach MF |

## Na co uważać

| Sytuacja | Co działa |
|---|---|
| Księgowa ma wystawiać faktury za firmę | uprawnienia nadane przez właściciela, nie jego certyfikat |
| Token wygenerowany w KSeF 1.0 | nie działa w KSeF 2.0, trzeba wygenerować nowy |
| Moduł KSeF w banku, np. Księgowość z Żubrem w Pekao | certyfikat pobrany z aplikacji MF i wgrany w banku |
| Faktura offline wręczana klientowi przed wysłaniem | certyfikat typu 2 wygenerowany wcześniej |

Według MF certyfikat jest osobistym poświadczeniem tożsamości. Nie pożycza się go.

[Firmowid](/cennik), nasz program, przyjmuje token albo certyfikat. Przy certyfikacie zapisuje datę wygaśnięcia.

## Źródła

- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/), dostęp 11.11.2026.
- [PKO Bank Polski: Faktury elektroniczne KSeF](https://www.pkobp.pl/firmy/uslugi-dla-firm/e-ksiegowosc/faktury-elektroniczne), dostęp 10.11.2026 (moduł certyfikatów MF).
- [Bank Pekao: KSeF](https://www.pekao.com.pl/przedsiebiorcy/uslugi-dodatkowe/ksef.html), dostęp 10.11.2026.
- Uprawnienia dla księgowej i biura: [dostęp do KSeF w JDG](/poradnik/dostep-do-ksef-jdg-i-ksiegowa).
