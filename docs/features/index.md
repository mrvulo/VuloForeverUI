# Features: Stand und Abnahme

Jedes Feature hat eine ID, einen Status und seine **Abnahmekriterien** — die
Prüfschritte im Spiel, nach denen es als fertig gilt. Claude führt diese Liste
bei jeder Änderung nach (siehe CLAUDE.md, „Arbeitsweise“). Wie ein Modul
gedacht ist und welche Regeln nie brechen dürfen, steht in
[../concepts.md](../concepts.md).

**Status:** `geplant` → `gebaut` (Checker grün, im Spiel ungetestet) →
`bestätigt` (vom Spieler im Spiel abgenommen). Ein Fehler setzt zurück auf
`gebaut`, mit einer Zeile unter „Offen“.

Abnahmekriterien in der Form **Angenommen … / Wenn … / Dann …**, damit sie
jemand ohne den Code prüfen kann.

---

## Übersicht

| ID | Feature | Modul | Status | Seit |
|---|---|---|---|---|
| F-01 | XP-Leiste (Overlay auf Client-Leiste, eigene Leiste) | Ressourcenleisten | bestätigt | 0.11.0 |
| F-02 | XP-Tempo über 15 Minuten | Ressourcenleisten | gebaut | – |
| F-03 | XP-Texte seitlich verschiebbar | Ressourcenleisten | gebaut | 0.12.0 |
| F-04 | Taschen-Stil Standard / Modern | Taschen | bestätigt | 0.12.0 |
| F-05 | Suchfeld mit Lupe, Platzhalter, Rand | Taschen | bestätigt | 0.12.0 |
| F-06 | Kategorien-Leiste: Pfeil, Symbole, Raster | Taschen | gebaut | – |
| F-07 | Berufstaschen-Farben, runde Ringe in beiden Stilen | Taschen | bestätigt | – |
| F-08 | Bank-Ansicht unterwegs im Standard-Stil | Taschen | gebaut | – |
| F-09 | Client-Taschen ohne Taint (Bankfach, Bearbeitungsmodus) | Taschen | gebaut | – |
| F-10 | Reagenzientaschen-Tutorial ausblenden | Taschen | gebaut | – |
| F-11 | Tooltip blinkt nicht über Taschenplätzen | Taschen | gebaut | – |
| F-12 | Neue Zauberränge ersetzen den alten | Aktionsleisten | gebaut | 0.12.0 |
| F-13 | Leisten über dem klassischen Band anheben | Aktionsleisten | bestätigt | 0.12.0 |
| F-14 | Freie Taschenplätze am Rucksack | Aktionsleisten | gebaut | 0.12.0 |
| F-15 | Nächster-Schlag-Fähigkeiten leuchten | Cooldown Manager | gebaut | – |
| F-16 | Schrift der Schadenszahlen | Globale Einstellungen | bestätigt | 0.12.0 |
| F-17 | Schnellplündern ohne aufblitzendes Fenster | Komfort | gebaut | 0.12.0 |
| F-18 | Sechs Sprachen, alle Namen übersetzt | Sprachen | gebaut | 0.12.0 |
| F-19 | Einrichtungs-Vorlagen mit echten Modulen | Einrichtung | gebaut | – |
| F-20 | Chat-Tabs ohne Fehler im Kampf | Chat | gebaut | 0.11.0 |
| F-21 | Gelbes „!“ auf Gegenständen, die eine Quest starten | Taschen | gebaut | – |
| F-22 | „Chat kopieren“ zeigt den Text | Chat | bestätigt | – |
| F-23 | Fenster „Mögliche Buffs“ mit Empfehlungen pro Rolle | Erinnerungen | gebaut | – |

---

## Abnahmekriterien

### F-02 XP-Tempo über 15 Minuten
- Angenommen du hast eine Weile gequestet, **wenn** du 20 Minuten Pause machst und weiterspielst, **dann** springen „EP/h“ und „Stufe in …“ nach wenigen Kills auf das aktuelle Tempo.
- Angenommen du hast gerade `/reload` gemacht, **dann** zeigt die Leiste den Sitzungsschnitt, bis neue Erfahrung kommt.

### F-06 Kategorien-Leiste
- Angenommen die Leiste ist zu, **dann** zeigt der Pfeil nach links; **wenn** du klickst, klappt sie auf und der Pfeil zeigt nach rechts.
- **Dann** sind alle Symbole 22 px, eckig, gleich gerahmt; nicht gewählte grau, gewählte farbig mit Goldrand und Goldbalken; Hover macht farbig.
- **Dann** stößt nichts an den Rahmen, zwischen Leiste und Plätzen liegt eine feine Linie.
- **Wenn** du eine neue Kategorie anlegst, **dann** zeigt sie das Symbol ihres ersten Gegenstands.

### F-07 Berufstaschen-Farben
- Angenommen eine Reagenzien- oder Berufstasche steckt, **dann** haben ihre Plätze den Farbrand der Taschenart — leer wie belegt, in jeder Ansicht und Kategorie, in beiden Stilen.
- Angenommen eine Leder-Reagenzientasche steckt, **dann** sind ihre Plätze **braun** wie Lederverarbeitung (nicht grün).
- **Dann** steht oben neben den freien Plätzen eine zweite Zahl für die Berufs-/Reagenzientasche (z. B. „6/6“), in derselben Farbe wie ihre Ränder; die normalen Plätze zählen sie nicht mit. *(Zahl wieder da: bestätigt 2026-10-08.)*
- **Wenn** „Abgerundete Plätze“ an ist, **dann** sind die Plätze auch im Standard-Stil rund mit rundem Ring (Qualität vor Taschenfarbe).

### F-08 Bank-Ansicht unterwegs
- Angenommen Stil Standard, **wenn** du im Taschenfenster den Münzknopf drückst, **dann** öffnet sich die Bank-Ansicht im Blizzard-Rahmen mit Bank-Porträt und „vom …“ rechts unter der Titelleiste.

### F-09 Client-Taschen ohne Taint
- Angenommen du öffnest und schließt die Taschen mehrmals und gehst zur Bank, **dann** kommt kein `ADDON_ACTION_FORBIDDEN … PurchaseBankTab()`.
- **Wenn** du danach den Bearbeitungsmodus öffnest und schließt, **dann** kommt kein Fehler aus `CompactUnitFrame`.
- **Dann** steht nach einigen Sitzungen kein Eintrag `taint` im Diagnoseprotokoll (Claude prüft den Rückkanal).

### F-10 Reagenzientaschen-Tutorial
- Angenommen eine Reagenzientasche liegt in den Taschen oder wurde gerade angelegt, **dann** steht kein gelber Kasten „Ihr habt eine Reagenzientasche erhalten!“ auf dem Bildschirm.

### F-11 Tooltip über Taschenplätzen
- **Wenn** du über einen Gegenstand fährst und stehen bleibst, **dann** bleibt der Tooltip stehen und verschwindet nicht kurz.
- **Dann** steht kein Eintrag `bags … hover lost` im Diagnoseprotokoll.

### F-12 Neue Zauberränge
- **Wenn** du beim Lehrer einen neuen Rang lernst, **dann** liegt er sofort auf jedem Platz, auf dem der bisher höchste Rang lag.
- Angenommen ein niedriger Rang liegt absichtlich auf einem anderen Platz, **dann** bleibt er dort.

### F-14 Freie Taschenplätze
- Angenommen die normalen Taschen sind voll, **dann** zeigt der Rucksack 0, auch wenn Köcher oder Berufstaschen leer sind.

### F-15 Nächster-Schlag-Fähigkeiten
- **Wenn** du Heldenhafter Stoß / Zermalmen / Raptorstoß einreihst, **dann** leuchtet das Symbol im Cooldown Manager gleichzeitig mit dem Aktionsleisten-Knopf und erlischt nach dem Schlag oder beim Abbrechen.

### F-17 Schnellplündern
- **Wenn** du mehrere Gegner hintereinander plünderst, **dann** blitzt kein Plünderfenster auf.
- Angenommen die Taschen sind voll, **dann** bleibt das Fenster in normaler Größe am gewohnten Platz stehen.

### F-18 Sprachen
- **Dann** zeigt die Seitenleiste des Optionsfensters „Globale Einstellungen“, „Komfort“, „Ressourcenleisten“, „Einheitenfenster“, „Profile“; die Reiter „Schriften“, „Stile“. *(Befehlsliste `/vfui help` auf Deutsch: bestätigt.)*
- **Wenn** du Français oder Русский wählst und neu lädst, **dann** erscheint die Oberfläche in der Sprache, kyrillisch ohne Kästchen.

### F-19 Einrichtungs-Vorlagen
- **Wenn** du `/vfui setup` mit „Minimal“ abschließt, **dann** sind Aktionsleisten, Auren, Cooldown Manager, Schadensmesser, Namensplaketten, Erinnerungen, Ressourcenleisten aus.
- **Wenn** du „Heiler“ wählst, **dann** öffnet der Schadensmesser auf Heilung.

### F-20 Chat-Tabs im Kampf
- **Wenn** du im Kampf `/reload` machst, **dann** kommt kein `ADDON_ACTION_BLOCKED` aus `Chat/Tabs.lua`.

### F-21 Quest-Starter markieren
- Angenommen ein Gegenstand startet eine Quest (z. B. Owatankas Schwanzstachel), **dann** trägt sein Platz das gelbe „!“ des Spiels, in beiden Stilen und jeder Platzgröße.
- **Wenn** du die Quest annimmst, **dann** verschwindet das „!“ sofort.
- **Wenn** du „Gegenstände markieren, die eine Quest starten“ ausschaltest, **dann** ist kein „!“ mehr da.

### F-22 Chat kopieren
- **Wenn** du in der Chat-Seitenleiste „Chat kopieren“ klickst, **dann** steht der Verlauf so da wie im Chat: Umlaute, Chinesisch, Koreanisch und Russisch zugleich lesbar, farbig, neueste Zeilen unten; Mausrad scrollt.
- **Wenn** du sofort Strg+C drückst, **dann** ist der ganze Verlauf in der Zwischenablage.
- **Wenn** du „Text markieren“ klickst, **dann** kannst du mit der Maus einen Teil markieren und mit Strg+C kopieren (Chinesisch/Koreanisch dort als Kästchen, kopiert werden die echten Zeichen); „Lesen“ schaltet zurück.

### F-23 Mögliche Buffs
- **Wenn** du unter Erinnerungen „Mögliche Buffs zeigen“ klickst, **dann** öffnet sich rechts neben dem Optionsfenster eine Liste: „Deine Zauber“, „Waffen“ (jede Waffenhand mit Restzeit, Gifte/Öle/Steine aus den Taschen), danach Fläschchen, Elixiere, Tränke, Rollen, Essen — jeweils mit Anzahl.
- Angenommen ein Buff ist auf dir (z. B. ein Elixier, „Satt“, Arkane Intelligenz), **dann** steht darunter grün „Aktiv · 25 Min.“; sonst grau „Nicht aktiv“. Trinkst du etwas, solange das Fenster offen ist, wechselt die Zeile von selbst.
- **Dann** zeigt Maus drüber den Tooltip; Escape oder das X schließt; das Fenster lässt sich ziehen.
- **Wenn** du oben die Rolle wechselst (Nahkampf-, Fernkampf-, Zauberschaden, Heiler, Tank), **dann** wechseln sofort die Empfehlungen: je Kategorie der beste Rang, den deine Stufe erlaubt (Stufe 20 sieht Stufe-20-Sachen), gold „Empfohlen · in den Taschen“ oder grau „nicht in den Taschen“.
- **Dann** stehen unter „Von anderen Klassen“ die Gruppenbuffs für deine Rolle mit Klassennamen in Klassenfarbe — Ausdauer, Mal der Wildnis, Könige, Macht usw., für beide Fraktionen; ab Stufe 55 kommen die Weltbuffs dazu.
- Angenommen ein Schurke, **dann** werden Sofort- und Tödliches Gift empfohlen. Jede Nahkampf- und Tankrolle (auch Schamane) bekommt Elementarwetzstein und Wetzstein, mit Streitkolben oder Stab Gewichtsstein statt Wetzstein.

---

## Offen

- 2026-10-09: schwarzer Balken links an der Namensplakette des Ziels, nach dem
  Schrifttest (`/vfdiag fonts`) und den Kopierfenster-Umbauten; nach einem
  Neustart des Clients weg. Ursache unbekannt. Taucht er wieder auf: Maus
  drauf, `/vfdiag mouse`, `/reload`, dann Rückkanal lesen.
