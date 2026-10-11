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
| F-22 | „Chat kopieren“ zeigt den Text | Chat | gebaut | – |
| F-23 | Fenster „Mögliche Buffs“ mit Empfehlungen pro Rolle | Erinnerungen | gebaut | – |
| F-24 | Eigene DoTs auf Namensplaketten, auch ohne Plakettenkennung (PvP und PvE) | Namensplaketten | gebaut | – |
| F-25 | Mögliche Buffs: wer in der Gruppe den Buff geben kann | Erinnerungen | gebaut | – |
| F-26 | Erinnerung an Fläschchen, Elixier und Essen aus den Taschen | Erinnerungen | gebaut | – |
| F-27 | Mögliche Buffs anklickbar (wirken / benutzen) | Erinnerungen | gebaut | – |
| F-28 | Fenster-Skins: Charakter- und Betrachten-Fenster, Standard / Modern | Skins | gebaut | – |
| F-31 | Goldprüfung: zuverlässige Abfrage, fehlend ≠ null, mehr Zähler, aus dem Betrachten-Fenster | Komfort | gebaut | – |
| F-30 | Levelführer-Skin (Standard / Modern) | Skins | gebaut | – |
| F-29 | Schmuckstücke: Auswahl-Raster beim Drüberfahren, Vormerken im Kampf, Warteschlange respektiert Handwahl | Komfort | gebaut | – |
| F-32 | Bedrohung in Prozent am Ziel- und Fokusrahmen (Classic / Standard) | Einheitenfenster | gebaut | – |
| F-33 | Buffs und Debuffs abgerundet, Spirale und Ring in derselben Form | Auren | gebaut | – |
| F-34 | Goldprüfung aus dem Rechtsklick-Menü auf einen Spieler | Komfort | gebaut | – |

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
- **Dann** haben beide Ansichten („Lesen“ und „Text markieren“) dieselbe kleine Schrift und die Farben des Chats (Beute grün, Systemmeldungen gelb, Kanäle in ihrer Farbe); „|4Spieler:Spieler;“ steht als „Spieler“ da.
- **Wenn** du sofort Strg+C drückst, **dann** ist der ganze Verlauf in der Zwischenablage.
- **Wenn** du „Text markieren“ klickst, **dann** kannst du mit der Maus einen Teil markieren und mit Strg+C kopieren (Chinesisch/Koreanisch dort als Kästchen, kopiert werden die echten Zeichen); „Lesen“ schaltet zurück.

### F-23 Mögliche Buffs
- **Wenn** du unter Erinnerungen „Mögliche Buffs zeigen“ klickst, **dann** öffnet sich rechts neben dem Optionsfenster eine Liste: „Deine Zauber“, „Waffen“ (jede Waffenhand mit Restzeit, Gifte/Öle/Steine aus den Taschen), danach Fläschchen, Elixiere, Tränke, Rollen, Essen — jeweils mit Anzahl.
- Angenommen ein Buff ist auf dir (z. B. ein Elixier, „Satt“, Arkane Intelligenz), **dann** steht darunter grün „Aktiv · 25 Min.“; sonst grau „Nicht aktiv“. Trinkst du etwas, solange das Fenster offen ist, wechselt die Zeile von selbst.
- **Dann** zeigt Maus drüber den Tooltip; Escape oder das X schließt; das Fenster lässt sich ziehen.
- **Wenn** du oben die Rolle wechselst (Nahkampf-, Fernkampf-, Zauberschaden, Heiler, Tank), **dann** wechseln sofort die Empfehlungen: je Kategorie der beste Rang, den deine Stufe erlaubt (Stufe 20 sieht Stufe-20-Sachen), gold „Empfohlen · in den Taschen“ oder grau „nicht in den Taschen“.
- **Dann** stehen unter „Von anderen Klassen“ die Gruppenbuffs für deine Rolle mit Klassennamen in Klassenfarbe — Ausdauer, Mal der Wildnis, Könige, Macht usw., für beide Fraktionen; ab Stufe 55 kommen die Weltbuffs dazu.
- Angenommen ein Schurke, **dann** werden Sofort- und Tödliches Gift empfohlen. Jede Nahkampf- und Tankrolle (auch Schamane) bekommt Elementarwetzstein und Wetzstein, mit Streitkolben oder Stab Gewichtsstein statt Wetzstein.

### F-24 Eigene DoTs auf Namensplaketten
- Angenommen „Alle eigenen Debuffs“ ist an (Standard), **wenn** du einem gegnerischen Spieler (Schlachtfeld, Duell, Weltkampf) oder einem NPC deinen DoT gibst, **dann** erscheint er sofort auf seiner Plakette mit Restzeit und verschwindet, wenn er ausläuft.
- **Dann** stehen die DoTs anderer Spieler dort nicht (außer „Alle Debuffs anzeigen“ ist an).
- **Wenn** du „Alle eigenen Debuffs“ ausschaltest, **dann** zeigt die Plakette nur noch die Debuffs, die das Spiel für Plaketten markiert.

### F-25 Wer kann mir das geben
- Angenommen du bist in einer Gruppe, **dann** stehen unter „Von anderen Klassen“ zuerst die Buffs, die jemand in der Gruppe geben kann; die übrigen stehen unten, blass, mit „Niemand in deiner Gruppe“. Allein ist nichts blass.
- **Wenn** jemand der Gruppe beitritt oder sie verlässt, **dann** ordnet sich die Liste sofort neu.

### F-26 Erinnerung an Verbrauchsgüter
- **Wenn** unter Erinnerungen „Stil“ auf Standard steht, **dann** tragen die Symbole den Aktionsknopf-Rahmen des Spiels; Modern zeigt unseren Rand in der Farbe des Zustands (rot fehlt, gold läuft ab), mit „Abgerundete Symbole“ abgerundet wie die Taschen — in der Leiste und in der Vorschau gleich.
- Angenommen du bist in einem Dungeon, hast ein für deine Rolle passendes Elixier in den Taschen und keins aktiv, **dann** zeigt die Erinnerungsleiste dessen Symbol; ein Linksklick trinkt es, danach verschwindet das Symbol.
- Angenommen du hast nur Essen ohne „Satt“-Wirkung oder gar nichts Passendes dabei, **dann** erscheint kein Symbol.
- **Wenn** „Nur in Dungeons und Schlachtzügen“ aus ist, **dann** gilt das auch in der offenen Welt.

### F-27 Mögliche Buffs anklickbar
- **Wenn** du außerhalb des Kampfs im Fenster auf deinen eigenen Zauber klickst, **dann** wirkst du ihn; auf ein Elixier, Essen, einen Trank oder eine Rolle in den Taschen, **dann** wird es benutzt.
- **Wenn** du auf Gift, Öl oder Stein klickst, **dann** kommt es links auf die Waffenhand, rechts auf die Schildhand.
- Angenommen du bist im Kampf, **dann** tut ein Klick nichts und es kommt kein Fehler.

### F-28 Fenster-Skins
- Angenommen „Skins → Fenster-Skins → Stil“ steht auf **Standard**, **wenn** du das Charakterfenster (C) öffnest, **dann** bleibt der Blizzard-Rahmen, aber jeder Ausrüstungsplatz ist abgerundet und trägt einen Ring in der Qualitätsfarbe seines Gegenstands (leer: neutral).
- Angenommen **Modern**, **dann** ist das Fenster flach dunkel mit dünnem Rand: Titel, die Leiste „Stufe 5, Jäger“, Modellhintergrund, Werte-Bereich und Reiter in derselben dunklen Farbe; die Plätze ebenfalls abgerundet in Qualitätsfarbe. Nichts Helles oder Goldenes bleibt stehen.
- **Wenn** du jemanden betrachtest, **dann** sieht das Betrachten-Fenster im gewählten Stil genauso aus.
- **Wenn** „Gegenstandsstufe“ an ist, **dann** steht auf jedem belegten Platz die Stufe (auch beim Betrachten).
- **Wenn** „Verzauberungen als Text“ an ist, **dann** steht neben dem Platz der Name der Verzauberung bzw. von Öl/Gift/Stein auf der Waffe: Waffenhand links, Schildhand darüber, Fernkampf rechts hinter dem Munitionsplatz; nichts liegt auf einem anderen Platz.
- **Wenn** „Waffen-DPS“ an ist, **dann** steht neben Waffenhand, Schildhand (wenn Waffe) und Fernkampf „x.x DPS“, über der Verzauberung, wie im Original links der Waffenhand und rechts hinter dem Munitionsplatz.
- **Wenn** „Haltbarkeit“ an ist, **dann** zeigt jeder Platz mit Haltbarkeit seinen Prozentwert, gelb unter 50 %, rot unter 20 %.
- **Wenn** „Werte-Abschnitte“ an ist, **dann** lassen sich die Abschnitte rechts per Klick auf den Titel ein- und ausklappen, und der Zustand bleibt nach /reload.
- **Dann** wechselt jede Einstellung sofort im offenen Fenster, und im Kampf kommt kein Fehler (Einklappen wartet bis nach dem Kampf).
- **Dann** zeigt die Optionsseite unter „Fenster-Skins“ je eine Karte für Charakterfenster, Betrachten-Fenster und Levelführer: Symbol, Titel, Beschreibung, rechts Aus/Standard/Modern, ein Pfeil klappt die Einstellungen der Karte auf.

### F-29 Schmuckstück-Raster
- **Wenn** du mit der Maus auf einen Schmuck-Platz fährst, **dann** klappt ein Raster mit allen Schmuckstücken aus den Taschen auf, jedes mit seiner Abklingzeit; es schließt, sobald die Maus Platz und Raster verlässt.
- **Wenn** du im Raster links klickst, **dann** kommt das Schmuckstück in den oberen Platz, rechts in den unteren.
- Angenommen du bist im Kampf, **wenn** du klickst, **dann** wird es vorgemerkt (kleines Symbol unten rechts im Platz) und nach dem Kampf angelegt; ein zweiter Klick auf dasselbe hebt die Vormerkung auf.
- **Wenn** du Alt-Klick auf ein Schmuckstück im Raster machst, **dann** verschwindet es aus dem Raster; mit gedrückter Alt-Taste erscheinen ausgeblendete grau und lassen sich per Alt-Klick zurückholen.
- **Wenn** „Stil“ auf Standard steht, **dann** tragen beide Plätze den Aktionsknopf-Rahmen des Spiels (Bronzering, leer die offene Fassung) und sind so groß wie deine Aktionsknöpfe.
- Angenommen Stil Modern und „Abgerundete Plätze“ an (Standard), **dann** sind beide Plätze und jedes Feld im Raster abgerundet wie die Taschen, mit Ring in der Qualitätsfarbe; die Abklingzeit-Spirale folgt der runden Form; eine Vormerkung im Raster hat einen goldenen Ring.
- Angenommen die Warteschlange eines Platzes ist an, **wenn** du von Hand ein passives oder nicht gelistetes Schmuckstück anlegst (z. B. Reitgerte), **dann** bleibt es liegen; der Pfeil wird grau, bis du es wieder ablegst.

### F-30 Levelführer-Skin
- Angenommen das Levelführer-Addon ist geladen und die Karte „Levelführer“ steht auf Standard oder Modern, **dann** haben Guide-Fenster (Kopf, Schrittliste, Fußzeile) und die Kästen mit dem aktuellen Schritt samt „Step N“-Reiter den Tooltip-Rahmen des Spiels (Standard) bzw. flach dunkle Flächen mit dünnem Rand (Modern); keine hellen runden Rahmen mehr.
- **Dann** ist der Scrollbalken im Standard-Stil der des Spiels, im Modern-Stil der schmale Balken unserer Fenster.
- **Dann** ist der Wegpfeil gold (Standard) bzw. in der Akzentfarbe (Modern), und das Fenster „Active Targets“ samt Titel-Reiter hat denselben Rahmen; im Kampf neu geöffnet bekommt es ihn nach dem Kampf.
- **Wenn** du über einen Schritt in der Liste fährst, **dann** hellt er sich leicht auf und wird beim Verlassen wieder dunkel.
- **Wenn** du den Stil wechselst oder der Guide einen neuen Abschnitt lädt, **dann** sitzt der Skin sofort richtig; ausschalten wirkt nach /reload.

### F-31 Goldprüfung
- **Dann** überlappt in den Spalten nichts: lange Bezeichnungen enden in „…“, Beträge bleiben ganz lesbar.
- Angenommen ein Charakter unter Stufe 10 oder mit unter 10 Gold Höchststand, **dann** heißt das Urteil „Zu wenig Verlauf zum Urteilen“ (grau), nicht rot.
- Angenommen sehr viele Auktionen (≥ 500) und kaum Quests/Kills, **dann** heißt es „Wahrscheinlich ein Bank- oder Handelscharakter“ (blau).
- Angenommen eine Einkommensquelle wird nicht gemeldet, **dann** steht „Teilweise Daten“ bzw. eine Beobachtung „Nicht gemeldet: …“, und das Urteil ist höchstens gelb.
- **Wenn** du unten „Spieler“ klickst, **dann** erscheinen alle geprüften Charaktere mit Suche und sortierbaren Spalten (Name, Stufe, Höchststand, Urteil, letzter Scan); ein Klick öffnet ihre letzte Prüfung.
- **Wenn** du „Verlauf“ klickst, **dann** stehen die gespeicherten Scans des angezeigten Spielers mit Höchststand, Gesamteinkommen und Zuwachs.
- **Wenn** du jemanden betrachtest, **dann** steht unter dem Betrachten-Fenster ein Knopf „Goldprüfung“; ein Klick öffnet die Prüfung daneben und liest die Statistiken. Mit „Gold beim Betrachten prüfen“ passiert das bei jedem Betrachten von selbst.
- **Wenn** du zweimal kurz hintereinander prüfst, **dann** steht „Kurz warten …“ und die zweite Abfrage geht nach wenigen Sekunden von selbst raus.
- Angenommen der Spieler ist zu weit weg, du bist im Kampf oder der Erfolgsvergleich ist offen, **dann** sagt die Prüfung genau das statt nur „keine Statistiken“.
- **Dann** stehen Werte, die das Spiel nicht liefert, als „--“ da, und oben rechts „x / y Zähler lesbar“; neu sind „Durchschnittlich verdient pro Tag“, „Talentumverteilungen“, „Ehrenhafte Siege“; „Mich prüfen“ zeigt die eigenen Zahlen.

### F-32 Bedrohung in Prozent
- Angenommen Stil Classic oder Standard, **wenn** du unter Einheitenfenster „Bedrohung in Prozent“ einschaltest und einen Gegner angreifst, **dann** steht über dem Zielrahmen ein Kästchen mit deiner Bedrohung in Prozent, gefärbt gelb → orange → rot.
- **Dann** überdeckt das Kästchen im Classic-Stil weder Namen noch Porträt; ohne Bedrohung (außer Kampf) ist es weg.
- **Wenn** du den Schalter ausmachst, **dann** verschwindet das Kästchen beim nächsten Bedrohungswechsel; das rote Aggro-Leuchten bleibt.

### F-33 Auren abgerundet
- Angenommen „Abgerundete Symbole“ ist bei Buffs an, **dann** sind Symbol, Rand-Ring und Waffenverzauberungen abgerundet wie die Taschen.
- **Wenn** ein Buff abläuft, **dann** deckt die dunkle Spirale das Symbol bis an den Ring ab; zwischen Spirale und Ring bleibt kein heller Streifen (gilt ebenso für die runden Schmuck-Plätze unter Komfort).
- **Dann** blitzt am Ende der Laufzeit nichts Eckiges über die runden Ecken.

### F-34 Goldprüfung aus dem Rechtsklick-Menü
- Angenommen die Goldprüfung ist an, **wenn** du einen Spieler im Ziel- oder Gruppenrahmen rechts anklickst, **dann** steht unten im Menü „Goldprüfung“; ein Klick scannt ihn und öffnet das Fenster mit dem Ergebnis.
- **Wenn** du danach „Fokus setzen“ aus demselben Menü wählst, **dann** klappt das ohne Fehlermeldung über eine blockierte Aktion.
- Angenommen ein Name im Chat, **dann** gibt es den Eintrag nur, wenn der Spieler gerade Ziel, Fokus oder in deiner Gruppe ist; bei dir selbst und bei NPCs fehlt er.

---

## Offen

- 2026-10-09: schwarzer Balken links an der Namensplakette des Ziels, nach dem
  Schrifttest (`/vfdiag fonts`) und den Kopierfenster-Umbauten; nach einem
  Neustart des Clients weg. Ursache unbekannt. Taucht er wieder auf: Maus
  drauf, `/vfdiag mouse`, `/reload`, dann Rückkanal lesen.
