# Benchmark cache Dockera — PR #38

Raport pomiarów dla [Alergeek-Ventures/firmowid, PR #38](https://github.com/Alergeek-Ventures/firmowid/pull/38).
Pięć faz × trzy warianty × dwie repliki: **30/30 jobów builda zakończyło się sukcesem**.
Nie publikowano obrazów ani nie wykonywano deploymentu.

## Metoda i warianty

| Wariant | Containerfile i builder | Cache zewnętrzny |
|---|---|---|
| Oryginalny (`original`) | Oryginalny `deployment/Containerfile.app` przypięty do `c02674c38a4328283f4be670767e7834fe19ab0d`; domyślny builder Dockera | Brak |
| Warstwy (`layered`) | Przełożone warstwy, jak w zoptymalizowanym Containerfile; driver `docker-container` | Brak |
| Cache (`cached`) | Ten sam Containerfile i driver co `layered` | `gha`, `mode=max`; niezależne zakresy `firmowid-benchmark-1` i `firmowid-benchmark-2` |

Każdy job korzystał ze świeżej VM `ubuntu-latest` z 4 vCPU. Zakresy cache
pozostawały stałe między commitami scenariuszy: replika 1 korzystała z własnego
cache poprzednich faz, a replika 2 z drugiego, niezależnego cache.
Faza `seed` była zimna dla wszystkich wariantów.

W każdej fazie przygotowano jeden wygenerowany artefakt PO dla dokładnego SHA,
wspólny dla wszystkich sześciu jobów. Hashami zweryfikowano identyczność katalogu
PO między jobami. `SOURCE_COMMIT` i znacznik w PO zmieniały się z każdym commitem.
Dlatego nawet przypadek zmiany wyłącznie CSS wymagał kompilacji aplikacji po
zmianie katalogu tłumaczeń — nie był pełnym trafieniem cache aplikacji.

Czas jobu obejmuje checkout, konfigurację, build, eksport cache i akcje końcowe.
Nie obejmuje oczekiwania w kolejce ani wspólnego przygotowania tłumaczeń,
jednakowego dla wariantów. Eksport cache jest częścią czasu jobu, nie należy
dodawać go ponownie do wyniku.

## Wyniki

Wartości w sekundach, w kolejności **replika 1 / replika 2**. Mediana przy dwóch
próbach jest średnią tych dwóch wartości; nie oznacza estymacji stabilnego czasu CI.

| Faza | Oryginalny: repliki (mediana) | Warstwy: repliki (mediana) | Cache: repliki (mediana) | Eksport cache: repliki |
|---|---:|---:|---:|---:|
| Zimne zasilenie cache (`seed`) | 307 / 436 (371,5) | 432 / 353 (392,5) | 478 / 478 (478) | 60,9 / 59,3 |
| Źródło Elixir (`elixir-source`) | 422 / 313 (367,5) | 425 / 350 (387,5) | 148 / 175 (161,5) | 28,9 / 43,1 |
| Źródło CSS (`asset-source`) | 418 / 435 (426,5) | 304 / 412 (358) | 168 / 154 (161) | 45,9 / 37,9 |
| Manifesty npm (`npm-dependency`) | 415 / 415 (415) | 423 / 441 (432) | 176 / 152 (164) | 51,6 / 33,2 |
| Invalidacja manifestu Mix (`mix-manifest`) | 418 / 421 (419,5) | 417 / 414 (415,5) | 470 / 534 (502) | 41,0 / 83,6 |

### Co rzeczywiście zmieniono i wykonano

- **Seed:** wszystkie warianty wykonywały pełną kompilację; cache trzeba było
  dopiero wyeksportować.
- **Źródło Elixir:** jedynie nieszkodliwy komentarz w `lib/firmowid.ex`, nie zmiana
  funkcjonalności. W wariancie cached zależności pochodziły z cache, aplikacja
  była kompilowana ponownie.
- **Źródło CSS:** jedynie komentarz CSS; poprzedni komentarz Elixir wcześniej
  wycofano, aby przypadki były niezależne. Zależności w cached pochodziły z cache,
  ale aplikacja kompilowała się ponownie z powodu zmiany PO.
- **Manifesty npm:** dodano bezpośrednią zależność deweloperską `is-number` 7.0.0,
  już obecną tranzytywnie. Zmieniono manifesty, bez podbicia wersji pakietu ani
  poszerzenia zbioru zależności tranzytywnych. W cached zależności Elixir pochodziły
  z cache, a `npm ci` wykonało się ponownie. Zmianę npm usunięto przed fazą Mix.
- **Invalidacja manifestu Mix:** syntetyczny komentarz w `mix.exs` unieważnił
  warstwę zależności. Nie zmieniono wersji bibliotek ani `mix.lock`; to nie pomiar
  rzeczywistej aktualizacji biblioteki. Wszystkie warianty wykonywały pełną
  kompilację.

W logach BuildKit status `CACHED`, po którym pojawia się `DONE`, może oznaczać
materializację warstwy z cache. Nie należy liczyć tego jako wykonania kompilacji.

## Wnioski i ograniczenia

Cache `gha` warto zachować **warunkowo: dla workflow z przewagą zmian źródeł**.
W trzech zmierzonych fazach ze zmianami źródeł lub manifestów npm zachowano cache
zależności Elixir, a joby cached trwały 148–176 s. Nie był to przypadek builda
całkowicie z cache: zmiany SHA i PO nadal powodowały pracę przy aplikacji.

Zimny build i invalidacja zależności Mix były z cache wolniejsze. W fazie Mix
mediana wyniosła 502 s wobec 419,5 s dla oryginalnego builda; koszt eksportu cache
był istotną częścią jobu. Nie należy przedstawiać tej fazy jako aktualizacji
bibliotek, ale pokazuje ona koszt utraty cache zależności.

Samo przełożenie warstw nie wykazało spójnej korzyści na świeżym runnerze bez
trwałego cache. Porównanie `original` z `layered` obejmuje również zmianę drivera
buildera, więc nie izoluje wyłącznie kolejności instrukcji Containerfile.
Cache ograniczony do zależności jest możliwym przyszłym wariantem do zbadania;
**nie został zmierzony** i nie przypisujemy mu przewidywanych czasów.

Modele CPU różniły się wewnątrz pierwszych czterech faz — sprzęt nie był
kontrolowany. W fazie Mix wszystkie sześć jobów miało AMD EPYC 7763. Dwie repliki
na wariant nie dają gwarancji statystycznej; wyniki nie gwarantują czasu kolejnych
buildów, zwłaszcza po zimnym starcie lub zmianie zależności.

Opisane w [README](README.md#ci-cache-obrazów-dockera) 33 s dotyczą najlepszego
przypadku ponowienia tego samego SHA i artefaktu. Nie są typowym czasem CI po
zmianie źródeł ani prognozą dla pierwszego builda `main` po merge.

## Ślad pomiarowy i odtworzenie metody

| Faza | Run | Dokładny commit |
|---|---|---|
| `seed` | [37026982425](https://github.com/Alergeek-Ventures/firmowid/actions/runs/37026982425) | [0f7c9361cb8df25847dea417422315cec60f691e](https://github.com/Alergeek-Ventures/firmowid/commit/0f7c9361cb8df25847dea417422315cec60f691e) |
| `elixir-source` | [37032666053](https://github.com/Alergeek-Ventures/firmowid/actions/runs/37032666053) | [b1f2cbdbaf60ea8d808388f9b4a5bf6f7eefa696](https://github.com/Alergeek-Ventures/firmowid/commit/b1f2cbdbaf60ea8d808388f9b4a5bf6f7eefa696) |
| `asset-source` | [37033787024](https://github.com/Alergeek-Ventures/firmowid/actions/runs/37033787024) | [0c7404a02e4ee831c9a082c3c1c9fec68ae80c66](https://github.com/Alergeek-Ventures/firmowid/commit/0c7404a02e4ee831c9a082c3c1c9fec68ae80c66) |
| `npm-dependency` | [37034956905](https://github.com/Alergeek-Ventures/firmowid/actions/runs/37034956905) | [601d68a54873e9813e32b371efd910478d3e9fbb](https://github.com/Alergeek-Ventures/firmowid/commit/601d68a54873e9813e32b371efd910478d3e9fbb) |
| `mix-manifest` | [37036481775](https://github.com/Alergeek-Ventures/firmowid/actions/runs/37036481775) | [2c76fd041a45f3cbd767c8d461d9de2f6bf5e3e5](https://github.com/Alergeek-Ventures/firmowid/commit/2c76fd041a45f3cbd767c8d461d9de2f6bf5e3e5) |

Oryginalny Containerfile jest dostępny w
[commicie bazowym](https://github.com/Alergeek-Ventures/firmowid/blob/c02674c38a4328283f4be670767e7834fe19ab0d/deployment/Containerfile.app).
Tymczasowy workflow i plik scenariusza usunięto z końcowego drzewa PR-a, ale ich
historyczne wersje pozostają dostępne, między innymi w commicie seed:
[workflow](https://github.com/Alergeek-Ventures/firmowid/blob/0f7c9361cb8df25847dea417422315cec60f691e/.github/workflows/docker-cache-benchmark.yml)
i [scenariusz](https://github.com/Alergeek-Ventures/firmowid/blob/0f7c9361cb8df25847dea417422315cec60f691e/.github/docker-cache-benchmark-case.json).
Odtworzenie metody wymaga zachowania dokładnych wejść i kolejności faz oraz
niezależnych zakresów cache replik; historyczne wyniki nie gwarantują takich
samych czasów na nowych runnerach.
