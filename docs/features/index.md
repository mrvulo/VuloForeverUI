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
| F-26 | Erinnerung an Fläschchen, Elixier und Essen aus den Taschen; Vorrat-Zahl, läuft bald ab, Aktive mit Haken | Erinnerungen | gebaut | – |
| F-27 | Mögliche Buffs anklickbar (wirken / benutzen) | Erinnerungen | gebaut | – |
| F-28 | Fenster-Skins: Charakter- und Betrachten-Fenster, Standard / Modern | Skins | gebaut | – |
| F-31 | Goldprüfung: zuverlässige Abfrage, fehlend ≠ null, mehr Zähler, aus dem Betrachten-Fenster | Komfort | gebaut | – |
| F-30 | Levelführer-Skin (Standard / Modern / Karten) | Skins | gebaut | – |
| F-29 | Schmuckstücke: Auswahl-Raster beim Drüberfahren, Vormerken im Kampf, Warteschlange respektiert Handwahl, Vorrang kehrt zurück, Shift-Klick-Listen, Listen je Talentverteilung | Komfort | gebaut | – |
| F-32 | Bedrohung in Prozent am Ziel- und Fokusrahmen (Classic / Standard) | Einheitenfenster | gebaut | – |
| F-33 | Buffs und Debuffs abgerundet, Spirale und Ring in derselben Form | Auren | gebaut | – |
| F-34 | Goldprüfung aus dem Rechtsklick-Menü auf einen Spieler | Komfort | gebaut | – |
| F-35 | Durchschnittliche Gegenstandsstufe im Charakterfenster, Farbe wählbar | Skins | gebaut | – |
| F-36 | Taschen-voll-Helfer: Vorschlag zum Löschen und Plündern mit einem Klick | Taschen | gebaut | – |
| F-37 | Erinnerungen: Hinweis auf den Zweck und Knopf zur Buffs-Leiste des Cooldown Managers | Erinnerungen | gebaut | – |
| F-38 | Beim Händler mehrere Stapel kaufen, „Max“ = ein voller Stapel, Shift+„Max“ = bezahlbar und passt in die Taschen | Komfort | gebaut | – |
| F-39 | Schadensmesser: Umrandung und Schatten für alle Texte | Schadensmesser | gebaut | – |
| F-40 | Durchschnittliche Gegenstandsstufe im Betrachten-Fenster | Skins | gebaut | – |
| F-41 | Verzauberungstexte gekürzt und auf den Modellbereich begrenzt | Skins | gebaut | – |
| F-42 | Ausgelieferte Standards = Profil des Spielers (Werkzeug ship_profile.py) | Global | gebaut | – |
| F-43 | Classic-Spielerrahmen: Prozent links, Wert rechts wie beim Ziel | Einheitenfenster | gebaut | – |
| F-44 | Angeltaste: Angel, Köder, Auswerfen, Einholen mit einer Taste; Doppelklick, Schwimmer-Markierung | Komfort | gebaut | – |
| F-45 | Tägliches Wort: Wortspiel im Flug, /vfword | Komfort | gebaut | – |
| F-46 | DoT-Leisten am Ziel mit Stärke beim Neuwirken | Ressourcenleisten | gebaut | – |
| F-47 | Fensterplätze aus unserem Bearbeitungsmodus auch im Blizzard-Layout | Bearbeitungsmodus | verworfen | – |
| F-48 | Berufe-Tab: Symbol über Erzen und Kräutern | Komfort | gebaut | – |
| F-49 | DoT-Restzeit auf dem Symbol, grün wenn Nachwirken nichts abschneidet | Cooldown Manager | gebaut | – |
| F-50 | Funkeln auf dem nächsten Erz oder Kraut | Komfort | gebaut | – |
| F-51 | Freundesliste im dunklen Stil (Modern) | Skins | gebaut | – |
| F-52 | Neuer Zauberrang erscheint nicht doppelt in der Vorschau | Cooldown Manager | gebaut | – |
| F-53 | Talentbedingungen pro Symbol | Cooldown Manager | gebaut | – |
| F-54 | Menge im Teilen-Fenster eintippen | Komfort | gebaut | – |
| F-55 | Bannbare Buffs am feindlichen Ziel leuchten | Unit Frames | gebaut | – |
| F-56 | Schlüsselbund als einklappbarer Abschnitt im Taschenfenster | Taschen | gebaut | – |
| F-57 | Chat-Eingabezeile: Kanalname und Text in einer Schrift, Textcursor am Textende | Chat | gebaut | – |
| F-58 | Chat-Links treffen genau: Zeitstempel schreibt das Spiel | Chat | gebaut | – |
| F-59 | Klassen-Modul mit Tab je Klasse; Priester: Schild-Bogen und Bogen für Inneres Feuer | Klassen | gebaut | – |
| F-60 | Erinnerungen: eigene Vorwarnzeit für Essen und Lagerfeuer-Buff, Countdown auf ablaufenden Symbolen | Erinnerungen | gebaut | – |
| F-70 | Chat-Verlauf: Spielername in einer zurückgeholten Zeile anklicken und anflüstern | Chat | gebaut | – |
| F-71 | Angeln leichter skillen: Taste im Fenster festlegen, Skill-Anzeige, Stufen-Hinweis, Auto-Beute, Schwimmer hören, Waffen zurück | Komfort | gebaut | – |
| F-72 | Flugleiste: genaue Flugzeit aus den Flugpfaden des Clients, auch beim ersten Flug | Komfort | gebaut | – |
| F-73 | Zeilen mit älterem Zauberrang zeigen den höchsten bekannten Rang | Cooldown Manager | gebaut | – |
| F-74 | Angeln: schnell neu auswerfen mit Strg + Angeltaste | Komfort | gebaut | – |
| F-75 | Angeln: ganze Angelausrüstung anlegen, Angel nach Angelbonus | Komfort | gebaut | – |
| F-76 | Angeln: Ton, wenn der Fisch entkommt, und Erinnerung zum Neuauswerfen | Komfort | gebaut | – |
| F-77 | Angeln: Sitzungsstatistik | Komfort | gebaut | – |
| F-78 | Angeln: kurze Fangübersicht nach dem Einholen | Komfort | gebaut | – |
| F-79 | Taschen: „Am Rucksack anzeigen“ aus dem Währungsfenster zeigt die Währung in der Taschen-Kopfzeile | Taschen | gebaut | – |
| F-80 | Angeln: Mausrad (auch mit Shift/Strg/Alt) als Angeltaste | Komfort | gebaut | – |
| F-81 | Würfelliste: Gruppenbeute-Würfe als eine kompakte, verschiebbare Liste statt der Spiel-Fenster | Komfort | gebaut | – |
| F-82 | Erinnerungen: Klick auf die Essens-Erinnerung isst deine Wahl, sonst das zuletzt gegessene, sonst das beste Essen | Erinnerungen | gebaut | – |
| F-69 | Fenster des Spiels an der Titelleiste verschieben, Position bleibt gemerkt | Komfort | bestätigt | – |
| F-68 | Chat-Verlauf je Reiter: Flüstern kommt nach dem Einloggen im eigenen Reiter zurück | Chat | gebaut | – |
| F-67 | Handwerkstaschen als eigene, einklappbare Abschnitte im Taschenfenster | Taschen | gebaut | – |
| F-66 | Gold-Tooltip der Taschen: Tagesbilanz ist Verdient minus Ausgegeben, Charakterliste stimmt ab dem Einloggen | Taschen / Komfort | gebaut | – |
| F-65 | Makro-Fabrik: Essen, Trinken, Gesundheitsstein, Tränke, Seelen-, Zauber- und Feuerstein, Manaedelstein als Makros, die Stufe und Taschen folgen | Komfort | gebaut | – |
| F-64 | Erinnerungen: Essen per Rechtsklick aus den Taschen wählen | Erinnerungen | gebaut | – |
| F-63 | Goldprüfung: zwei Charaktere nebeneinander vergleichen | Komfort | gebaut | – |
| F-62 | Reit-Schmuckstück: beim Aufsitzen anlegen, beim Absitzen das vorherige zurück | Komfort | gebaut | – |
| F-61 | Händlerfenster: Gegenstände, die man schon hat (bekannte Rezepte, Reittiere, Haustiere, Spielzeuge), rot getönt | Skins | gebaut | – |

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
- **Wenn** du an der Bank ein Item aus den Taschen per Rechtsklick benutzt oder einlagerst, **dann** kommt kein `ADDON_ACTION_FORBIDDEN … UNKNOWN()`, auch nicht später in derselben Sitzung.
- Angenommen das erste Bankfach ist noch nicht gekauft, **dann** kauft es der Kaufknopf im Bankfenster ohne Fehler, und das Spiel kauft es nicht mehr von selbst.
- **Wenn** du das Bankfenster mit X oder Escape schließt, **dann** ist der Bankbesuch beendet; ein erneuter Klick auf den Bankier öffnet es wieder.
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
- **Dann** zeigt jedes Symbol, das ein Gegenstand aus den Taschen ist (Fläschchen, Elixier, Essen, Gift/Öl/Stein), unten rechts, wie viele du davon hast; liegt die Zahl bei oder unter „Wenig Vorrat ab“ (Standard 3), ist sie rot. 0 schaltet die Warnung ab.
- Angenommen „Warnen, bevor es ausläuft“ steht auf 5 Minuten, **wenn** dein Fläschchen, Elixier oder „Satt“ noch weniger als 5 Minuten hat, **dann** erscheint sein Symbol mit goldenem Rand („Läuft bald ab“), ein Linksklick erneuert es.
- Angenommen „Aktive mit Haken zeigen“ ist an, **dann** bleiben Buffs, Waffenverzauberungen und Verbrauchsgüter, die gerade auf dir sind, in der Leiste: grau, mit grünem Haken und grünem Rand, ohne Pulsieren; ein Linksklick tut nichts. Läuft eins bald ab oder fehlt es, wird es wieder farbig und anklickbar. Ein aktives Verbrauchsgut, von dem nichts mehr in den Taschen ist, zeigt eine rote 0.
- **Dann** zeigt die Vorschau auf der Optionsseite Haken und Zahl genauso.

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
- **Wenn** du mit der Maus auf einen Schmuck-Platz fährst, **dann** klappt an genau diesem Platz (mittig darüber bzw. darunter, bei gestapelten Plätzen daneben) ein Raster mit allen Schmuckstücken aus den Taschen auf, jedes mit seiner Abklingzeit; fährst du auf den anderen Platz, wandert das Raster mit; es schließt, sobald die Maus Platz und Raster verlässt.
- **Wenn** du im Raster links klickst, **dann** kommt das Schmuckstück in den Platz, an dem das Raster hängt; ein Rechtsklick legt es in den anderen Platz.
- Angenommen du bist im Kampf, **wenn** du klickst, **dann** wird es vorgemerkt (kleines Symbol unten rechts im Platz) und nach dem Kampf angelegt; ein zweiter Klick auf dasselbe hebt die Vormerkung auf.
- **Wenn** du Alt-Klick auf ein Schmuckstück im Raster machst, **dann** verschwindet es aus dem Raster; mit gedrückter Alt-Taste erscheinen ausgeblendete grau und lassen sich per Alt-Klick zurückholen.
- **Wenn** „Stil“ auf Standard steht, **dann** tragen beide Plätze den Aktionsknopf-Rahmen des Spiels (Bronzering, leer die offene Fassung) und sind so groß wie deine Aktionsknöpfe.
- Angenommen Stil Modern und „Abgerundete Plätze“ an (Standard), **dann** sind beide Plätze und jedes Feld im Raster abgerundet wie die Taschen, mit Ring in der Qualitätsfarbe; die Abklingzeit-Spirale folgt der runden Form; eine Vormerkung im Raster hat einen goldenen Ring.
- Angenommen die Warteschlange eines Platzes ist an, **wenn** du von Hand ein passives oder nicht gelistetes Schmuckstück anlegst (z. B. Reitgerte), **dann** bleibt es liegen; der Pfeil wird grau, bis du es wieder ablegst.
- Angenommen die Warteschlange eines Platzes ist an und im Platz steckt ein bereites Schmuckstück von Rang 2, **wenn** das Schmuckstück von Rang 1 in der Tasche wieder bereit ist (höchstens 30 s Abklingzeit), **dann** kommt es außerhalb des Kampfes zurück in den Platz; ein Schmuckstück, das du in den letzten 20 s benutzt hast, bleibt bis dahin stecken, eines, das du selbst angelegt hast, bis es verbraucht ist.
- **Wenn** du im Raster Shift-Linksklick auf ein Schmuckstück machst, **dann** kommt es in die Liste des Platzes, an dem das Raster hängt (über die Stoppmarke), bzw. fliegt wieder heraus; Shift-Rechtsklick tut dasselbe für den anderen Platz. Die Optionsseite zeigt die Änderung sofort.
- **Dann** trägt jedes Feld im Raster, das in einer Liste steht, links oben seinen Rang in der oberen Liste (gold) und links unten den in der unteren (blau); unter der Stoppmarke grau.
- Angenommen du hast die Doppelspezialisierung, **wenn** du die Talentverteilung wechselst, **dann** gelten die Listen (und ihr An/Aus) dieser Verteilung; die Optionsseite nennt, welche gerade bearbeitet wird. Beim ersten Start mit dieser Version bekommen beide Verteilungen eine Kopie der bisherigen Listen.

### F-30 Levelführer-Skin
- Angenommen das Levelführer-Addon ist geladen und die Karte „Levelführer“ steht auf Standard oder Modern, **dann** haben Guide-Fenster (Kopf, Schrittliste, Fußzeile) und die Kästen mit dem aktuellen Schritt samt „Step N“-Reiter den Tooltip-Rahmen des Spiels (Standard) bzw. flach dunkle Flächen mit dünnem Rand (Modern); keine hellen runden Rahmen mehr.
- **Dann** ist der Scrollbalken im Standard-Stil der des Spiels, im Modern-Stil der schmale Balken unserer Fenster.
- **Dann** ist der Wegpfeil gold (Standard) bzw. in der Akzentfarbe (Modern), und das Fenster „Active Targets“ samt Titel-Reiter hat denselben Rahmen; im Kampf neu geöffnet bekommt es ihn nach dem Kampf.
- **Wenn** du über einen Schritt in der Liste fährst, **dann** hellt er sich leicht auf und wird beim Verlassen wieder dunkel.
- **Wenn** du den Stil wechselst oder der Guide einen neuen Abschnitt lädt, **dann** sitzt der Skin sofort richtig; ausschalten wirkt nach /reload.
- Angenommen Stil „Karten“ (nach einem Neustart des Spiels, wegen der neuen Texturen), **dann** ist jeder Schritt der Liste und jeder Kasten mit dem aktuellen Schritt samt Nummer eine eigene abgerundete, dunkle schieferblaue Karte mit hellerem dünnem Rand; das Zonenbild im Kopf bleibt sichtbar, Scrollbalken und Wegpfeil wie bei Modern.

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

### F-35 Durchschnittliche Gegenstandsstufe im Charakterfenster
- Angenommen der Charakterfenster-Skin ist an (Standard oder Modern), **wenn** du das Charakterfenster öffnest, **dann** steht in der Stufen-Leiste zwischen „Stufe 24, Schamanin“ und dem Pfeil-Knopf mittig „iLvL 22“ (Durchschnitt der angelegten Ausrüstung, abgerundet wie in den Werten).
- Angenommen Farbe „Nach Qualität“, **dann** hat der Text die Farbe der durchschnittlichen Qualität deiner Teile (meist grün); mit „Eigene Farbe“ die gewählte Farbe, sofort beim Ändern.
- **Wenn** du ein Teil wechselst, **dann** ändert sich der Wert gleich; mit dem Schalter aus oder dem Skin auf „Aus“ ist der Text weg.

### F-36 Taschen-voll-Helfer
- Angenommen die allgemeinen Taschen sind voll, **wenn** du plünderst und „Inventar ist voll“ kommt, **dann** erscheint unter dem Beutefenster eine Leiste „Taschen voll“ mit Symbol, Name und Händlerwert eines Stapels.
- **Dann** ist der Vorschlag Schrott (grau oder markiert), solange es welchen gibt, sonst der billigste andere Stapel; „Anderer“ blättert durch die übrigen Vorschläge.
- **Nie** vorgeschlagen werden Quest-Gegenstände, Berufswerkzeuge (Spitzhacke, Kürschnermesser, Schmiedehammer, Runenrute …), Klassenreagenzien, Munition, Köcher, Taschen, Schlüssel, Gegenstände ohne Verkaufswert, angepinnte Gegenstände, Rüstung/Waffen über Grau und alles ab Selten (blau). Nichts davon → „Nichts in deinen Taschen kann gefahrlos weg.“
- **Wenn** du „Löschen & plündern“ klickst, **dann** verschwindet der Stapel (Chatzeile „Taschen voll: … zerstört“) und die liegengebliebene Beute landet in den Taschen; passt danach noch etwas nicht, kommt der nächste Vorschlag.
- Angenommen die Beute passt auf einen angefangenen Stapel oder ein Platz ist frei, **dann** erscheint keine Leiste; beim Schließen des Beutefensters geht sie weg.

### F-37 Erinnerungen: Zweck und Verweis auf die Buffs-Leiste
- **Wenn** du die Erinnerungen-Seite öffnest, **dann** steht ganz oben grau: für Buffs und Verbrauchsgüter außerhalb des Kampfes; Buffs und Procs im Kampf gehören in die Buffs-Leiste des Cooldown Managers.
- **Wenn** du „Buffs-Leiste öffnen“ klickst, **dann** springt das Fenster zum Cooldown Manager, Reiter „Zauber“, mit der Leiste „Buffs“ ausgewählt; gibt es keine Buffs-Leiste, steht die erste Leiste da (mit „Neue Stärkungszauberleiste hinzufügen“).

### F-38 Beim Händler mehrere Stapel kaufen
- Angenommen genug Gold und freie Plätze, **wenn** du beim Händler Shift auf Wasser klickst, **dann** geht Blizzards Fenster über 20 hinaus, und „Max“ trägt genau einen vollen Stapel ein (Wasser: 20).
- **Wenn** du mit Shift auf „Max“ klickst, **dann** trägt es so viele ein, wie in deine Taschen passen (freie Plätze plus angefangene Stapel), höchstens was dein Gold hergibt und der Händler vorrätig hat.
- **Wenn** du „Okay“ klickst, **dann** kauft das Addon Stapel für Stapel (kurz hintereinander), und im Chat steht „N x … gekauft.“; schließt du den Händler mittendrin, hört es auf.
- Angenommen eine Menge bis zu einem Stapel, **dann** kauft das Spiel wie gewohnt selbst. Waren, die mit Gegenständen bezahlt werden, behalten die Grenze des Spiels.

### F-39 Schadensmesser: Umrandung und Schatten
- **Wenn** du im Reiter „Text“ die Umrandung auf „Dicke Umrandung“ stellst, **dann** bekommen sofort alle Texte des Messers (Namen, Zahlen, Kopfzeile, Aufschlüsselung) den Rand; „Aus den Schrifteinstellungen“ nimmt wieder den aus Globale Einstellungen → Schriften.
- **Wenn** du „Schatten“ einschaltest, **dann** liegt unter jedem Text ein dunkler Schatten (1 px nach rechts unten), sofort sichtbar; aus = kein Schatten.
- Angenommen „Glatte Umrandung“ ist an und der Client kann es, **dann** hat die Umrandung weiche, gleichmäßige Kanten statt Pixelstufen; kann der Client es nicht, ist der Schalter grau.
- Angenommen Timer oder Bedrohungsmesser haben eine eigene Umrandung gewählt, **dann** behalten sie diese; auf „Aus den Schrifteinstellungen“ folgen sie dem Messer.

### F-40 Durchschnittliche Gegenstandsstufe im Betrachten-Fenster
- Angenommen der Betrachten-Skin ist an, **wenn** du einen Spieler betrachtest, **dann** steht rechts neben „Stufe 30, Jäger“ „iLvL …“ (der Wert des Spiels für diesen Spieler), sobald seine Daten da sind.
- **Dann** hat der Text dieselbe Farbregel wie dein Charakterfenster (nach Qualität seiner Teile oder deine eigene Farbe) und überlappt weder den Stufentext noch den Rahmen.
- **Wenn** du „Durchschnittliche Gegenstandsstufe anzeigen“ in der Karte Betrachten-Fenster ausschaltest, **dann** ist der Text weg.

### F-41 Verzauberungstexte gekürzt
- **Wenn** du Charakter- oder Betrachten-Fenster öffnest, **dann** stehen Verzauberungen kurz da: „Ausdauer +3 und Rüstung +10“ → „Ausd +3, Rüst +10“, „Beweglichkeit +5“ → „Bew +5“, „Schwache Tempo-Steigerung“ → „Tempo“.
- **Dann** bleiben die Texte im Modellbereich zwischen den Platz-Spalten: jede Seite höchstens bis zur Mitte, linke und rechte Texte derselben Zeile berühren sich nie; was trotzdem zu lang ist, endet in „…“.
- Angenommen ein englischer Client, **dann** gilt dasselbe mit „Sta“, „Agi“, „Arm“ usw.; andere Sprachen behalten den Text und werden nur begrenzt.

### F-42 Ausgelieferte Standards aus dem Spielerprofil
- Angenommen ein neuer Charakter ohne eigene Einstellungen (oder „Modul zurücksetzen“), **dann** sieht alles aus wie auf Vulo: Classic-Einheitenfenster, abgerundete Auren, Taschen mit BoE und Positionen, Schadensmesser mit Umrandung, Ressourcenleisten, Schrift Expressway auch für Spieltext.
- **Dann** sind alle Module an außer dem Cooldown Manager.
- Angenommen ein Spieler hat etwas selbst eingestellt, **dann** bleibt sein Wert; nur nie geänderte Einstellungen bekommen den neuen Standard.
- Angenommen ein Krieger mit eigener Cooldown-Manager-Leiste, **dann** stehen dort keine Schamanen-Zauber.

### F-43 Classic-Spielerrahmen: Statustext wie beim Ziel
- Angenommen Stil Classic und „Statustext auf den Balken“ an, **dann** zeigt der Spielerrahmen „100%“ links und „594“ rechts auf dem Lebensbalken, beim Mana „100%“ und „796“ — in Höhe und Schrift genau wie der Zielrahmen daneben; kein mittiges „594 / 594“ mehr.
- **Wenn** du Schaden nimmst oder Mana verbrauchst, auch im Kampf, **dann** laufen Prozent und Wert mit.
- Angenommen Wut oder Energie, **dann** steht nur der Wert (wie bei Blizzard). Tot, als Geist oder im Fahrzeug zeigt der Rahmen wieder Blizzards eigenen Text.
- **Wenn** du „Statustext auf den Balken“ ausschaltest, **dann** sind unsere Texte weg und Blizzards Anzeige ist zurück.
- **Dann** sitzen bei Spieler, Ziel und Fokus alle Balkentexte auf den sichtbaren Balken: in der Höhe mittig, links und rechts mit demselben Abstand (3 px) zum Balkenrand, Leben und Mana gleich.
- **Wenn** du im Kampf ein neues Ziel nimmst, **dann** bleibt dessen HP-Wert rechts im Lebensbalken und springt nicht neben das Porträt.
- **Wenn** du Schaden bekommst (deutscher Client), **dann** steht die Schadenszahl mittig auf deinem Porträt, nicht nach links versetzt.

### F-44 Angeltaste
- Angenommen eine Taste ist unter Tastenbelegung → AddOns → „VuloForeverUI: Angeln“ belegt und eine Waffe in der Hand, **wenn** du die Taste drückst, **dann** legt sie die Angel aus den Taschen an; nächster Druck: der beste Köder, den dein Angelskill erlaubt (wenn keiner drauf ist); nächster Druck: Auswerfen.
- **Wenn** der Schwimmer draußen ist und anbeißt, **dann** holt dieselbe Taste ihn ein (Beute öffnet sich); über dem Schwimmer sitzt das Interaktionssymbol des Spiels.
- **Dann** sind deine Soft-Target-Einstellungen ein paar Sekunden nach dem Angeln wieder wie vorher — auch nach Kampf oder `/reload` mitten im Angeln.
- Angenommen „Mit Doppel-Rechtsklick auswerfen“ ist an, **wenn** du mit der Angel in der Hand schnell zweimal rechts in die Welt klickst, **dann** wirft sie aus; einfacher Rechtsklick dreht weiter die Kamera, und im Kampf verhält sich Rechtsklick ganz normal.
- **Wenn** „Angeltaste“ aus ist, **dann** tut die belegte Taste nichts.

### F-71 Angeln leichter skillen
- Angenommen `/vfui → Komfort → Angeln` ist offen, **wenn** du „Taste festlegen“ klickst und eine Taste drückst (auch mit Shift, Strg oder Alt, oder Maustaste 3 bis 5 über dem kleinen Fenster), **dann** ist sie die Angeltaste, „Aktuelle Taste“ zeigt sie, und der Chat sagt, was vorher auf ihr lag. Eine vorher belegte Angeltaste ist danach frei. Esc bricht ab; ein Kampf schließt das Fenster.
- **Wenn** du „Taste entfernen“ klickst, **dann** ist keine Angeltaste mehr belegt und der rote Hinweis steht wieder da.
- Unter „Skillen“ steht „Angelskill: 215 / 225“ (ohne Angeln: ein roter Hinweis).
- Angenommen „Melden, wenn eine Stufe voll ist“ ist an, **wenn** der Skill das Maximum seiner Stufe erreicht (75/75, 150/150, 225/225), **dann** sagt eine Zeile im Chat, dass die nächste Stufe beim Angellehrer wartet — einmal je Stufe, auch nicht wieder nach `/reload`.
- Angenommen „Beute beim Angeln automatisch aufheben“ ist an und das automatische Plündern des Spiels aus, **wenn** du einholst, **dann** landet der Fang ohne Klick in der Tasche; ein paar Sekunden nach dem Angeln ist das Spiel wieder auf deiner Einstellung.
- Angenommen „Schwimmer besser hören“ ist an, **wenn** die Leine draußen ist, **dann** sind Effekte voll und ohne Dämpfung über die Entfernung, Musik, Umgebung, Stimmen und Nebengeräusche (Begleiter, Emotes, Rüstungsrascheln, Fehlerstimme) stumm, auch mit dem Spiel im Hintergrund — der Platscher hebt sich deutlich ab; ein paar Sekunden nach dem Angeln sind deine Lautstärken zurück.
- Angenommen „Waffen beim Aufsitzen zurück“ ist an und die Angeltaste hat die Angel angelegt, **wenn** du aufsitzt, **dann** liegen die Waffen von vorher wieder in den Händen. Hast du inzwischen selbst etwas anderes angelegt, passiert nichts.

### F-72 Genaue Flugzeit beim ersten Flug
- Angenommen eine Route ist noch nie geflogen (z. B. Burg Cenarius → Gadgetzan), **wenn** du abfliegst, **dann** zeigt die Flugleiste die Gesamtzeit ohne „~“, und du landest höchstens ein paar Sekunden neben ihr.
- **Dann** stehen auch die Zeiten bis zu den Zwischenstopps im Streifen unter der Leiste ohne „~“ und stimmen auf wenige Sekunden.
- **Wenn** eine Route schon geflogen ist, **dann** gilt die gemessene Zeit wie bisher.
- **Wenn** eine Zeit abläuft, während du noch in der Luft bist, **dann** steht im Streifen „gleich“ statt „~0:00“.

### F-73 Höchster bekannter Rang
- Angenommen ein Zauber mit Abklingzeit steht mit Rang 1 auf einer Leiste, **wenn** du Rang 2 lernst, **dann** bleibt das Symbol an seinem Platz, der Tooltip zeigt Rang 2, und nach dem Wirken von Rang 2 läuft die Abklingzeit auf dem Symbol.
- Angenommen ein Buff steht mit „Aktive Phase anzeigen“ und einer älteren Rang-ID auf der Leiste (auch per ID hinzugefügt), **wenn** du den höchsten Rang wirkst, **dann** zeigt das Symbol außerhalb des Kampfes die ablaufende Buffdauer.
- Angenommen eine Zeile hat eigene Einstellungen (z. B. Glühen), **wenn** du den neuen Rang über „+“ noch einmal auf dieselbe Leiste setzt, **dann** bleibt die Zeile an ihrem Platz und behält ihre Einstellungen; auf eine andere Leiste wandert sie mit ihren Einstellungen ans Ende.

### F-74 Schnell neu auswerfen
- Angenommen „Schnell neu auswerfen mit Strg“ ist an und die Leine ist draußen, **wenn** du Strg + Angeltaste drückst, **dann** bricht der Wurf ab und die Angel wirft sofort neu aus, ohne Angel oder Köder anzufassen.
- **Wenn** die Leine nicht draußen ist, **dann** macht Strg + Angeltaste das, was du selbst darauf gelegt hast.
- Angenommen die Angeltaste trägt schon Strg, **dann** gibt es keinen schnellen Neuwurf.

### F-75 Angelausrüstung
- Angenommen „Angelausrüstung anlegen“ ist an und in der Tasche liegt gebundene Ausrüstung mit Angelbonus (z. B. ein Angelhut, Stiefel, Handschuhe mit Angel-Verzauberung), **wenn** du die Angeltaste drückst, **dann** wird sie angelegt, wo sie mehr Angelbonus bringt als das Getragene.
- **Dann** nimmt die Angeltaste die Angel mit dem höchsten Angelbonus aus der Tasche, nicht die mit der höchsten Gegenstandsstufe.
- Angenommen „Waffen und Ausrüstung beim Aufsitzen zurück“ ist an, **wenn** du aufsitzt, **dann** liegen Waffen und die vorher getragenen Teile wieder an. Was du inzwischen selbst getauscht hast, bleibt.
- Ungebundene Teile werden nicht angefasst (kein Bindungsfenster).
- Teile und Angeln, für die dein Angelskill noch zu niedrig ist, werden übergangen (keine rote Fehlermeldung bei jedem Druck).

### F-76 Entkommen und Neuwurf
- Angenommen „Ton, wenn der Fisch entkommt“ ist an, **wenn** der Fisch entkommt oder du klickst, bevor etwas angebissen hat, **dann** spielt der gewählte Warnton.
- Angenommen „Erinnern, neu auszuwerfen“ ist an, **wenn** du nach dem Einholen still stehst und die eingestellten Sekunden nicht neu auswirfst, **dann** spielt der Warnton einmal. Wer läuft, reitet oder kämpft, hört nichts.
- Unter „Warnton“ stehen „Bereitschaftscheck“, „Schlachtzugswarnung“ und die Töne geteilter Medien; die Wahl spielt sofort zur Probe.

### F-77 Sitzungsstatistik
- **Wenn** du angelst, **dann** steht unter `/vfui → Komfort → Angeln → Sitzung` „Würfe, Fänge (Quote), pro Stunde, Angelzeit“ und zählt mit; auch nach `/reload`.
- **Wenn** du 30 Minuten nicht angelst, **dann** beginnt der nächste Wurf eine neue Sitzung; „Sitzung zurücksetzen“ beginnt sofort eine.

### F-78 Fangübersicht
- Angenommen „Fang kurz zeigen“ ist an, **wenn** du einholst, **dann** zeigt sich über der Bildschirmmitte ein paar Sekunden Symbol, Menge und Name jedes Fangs in Qualitätsfarbe, darunter grau die Fänge der Sitzung und pro Stunde; danach blendet es aus.
- **Dann** verdeckt es keine Klicks (die Maus geht hindurch).

### F-79 Rucksack-Währungen in den Taschen
- Angenommen „Am Rucksack angezeigte Währungen“ ist an, **wenn** du im Währungsfenster des Spiels bei einer Währung (z. B. Händlergunst) „Am Rucksack anzeigen“ ankreuzt, **dann** steht sie mit Symbol und Menge sofort in der Kopfzeile der offenen Taschen, vor dem Gold.
- **Wenn** du das Häkchen wieder entfernst, **dann** verschwindet sie, außer sie ist auch unter „Aktivierte Währungen“ gewählt; doppelt steht keine Währung da.
- **Wenn** sich die Menge ändert, **dann** zieht die Zahl mit.


### F-80 Mausrad als Angeltaste
- **Wenn** du unter Komfort → Angeln „Taste festlegen“ drückst und über dem Fenster das Mausrad drehst (gern mit Shift, Strg oder Alt), **dann** ist „Mausrad hoch“ bzw. „Mausrad runter“ mit diesem Zusatz die Angeltaste, und die Seite zeigt sie an.
- **Wenn** du mit der Angel in der Hand einmal am Rad drehst, **dann** wirfst du genau einmal aus — die restlichen Rasten desselben Drehs holen die Leine nicht gleich wieder ein und werfen nicht neu aus.
- **Wenn** der Schwimmer anbeißt und du am Rad drehst, **dann** holst du ein wie mit einer Taste; Strg + Rad wirft bei draußener Leine sofort neu aus (wenn „Schnell neu auswerfen“ an ist).
- Bekannte Grenze: Rund eine Sekunde nach dem Auswerfen holt das Rad noch nicht ein; vorher beißt ohnehin nichts.

### F-82 Essens-Erinnerung: was ein Klick isst
- **Angenommen** du hast per Rechtsklick ein Essen gewählt und trägst es, **wenn** du die Essens-Erinnerung links anklickst, **dann** isst du genau dieses.
- **Angenommen** „Automatisch“ ist gewählt und du hast zuletzt ein Essen gegessen, das dich satt gemacht hat, **wenn** die Erinnerung wiederkommt, **dann** zeigt sie dieses Essen mit Anzahl, und ein Klick isst es wieder — auch wenn es nicht das Rollen-Essen ist.
- **Angenommen** davon ist nichts mehr in den Taschen, **dann** zeigt sie das beste Essen deiner Rolle; fehlt auch das, das beste bekannte Buff-Essen, das deine Stufe essen darf.
- **Wenn** du im Fenster „Mögliche Buffs“ auf die Zeile „Satt“ fährst, **dann** nennt der Tooltip „Linksklick: <Essen> essen“, und ein Klick isst nach derselben Reihenfolge.
- **Wenn** du nur trinkst, **dann** merkt sich die Erinnerung das Getränk nicht; isst und trinkst du gleichzeitig, merkt sie sich nur ein bekanntes Buff-Essen.
- Bekannte Grenze: „Zuletzt gegessen“ zählt erst, wenn binnen 60 Sekunden nach dem Essen ein bekannter Essens-Buff kommt, und nur bei eingeschalteten Erinnerungen. Gilt pro Charakter.

### F-81 Würfelliste
- **Angenommen** „Würfelliste“ ist an (Standard: aus), **wenn** in der Gruppe ein Gegenstand ausgewürfelt wird, **dann** erscheinen nicht mehr die Würfelfenster des Spiels, sondern eine Zeile in unserer Liste: Symbol mit Anzahl, Name in Qualitätsfarbe, „BoE“ bei Gegenständen, die beim Anlegen binden, ein Zeitbalken in Qualitätsfarbe mit Restzeit, rechts Bedarf, Gier (bzw. Transmog), Entzaubern (nur wenn möglich) und Passen.
- **Wenn** du auf einen der Knöpfe klickst, **dann** würfelst du genau so wie im Spiel-Fenster; ein Seelengebunden-Gegenstand fragt wie gewohnt nach. Ein Knopf, den du nicht nehmen darfst, ist grau, und sein Tooltip nennt den Grund.
- **Dann** steht unter jedem Knopf, wie viele diese Wahl schon getroffen haben; über der Zeile zeigt ein Tooltip alle Spieler in Klassenfarbe mit ihrer Wahl („?“ = noch offen) und nach dem Ende die Wurfzahlen. Über dem Symbol zeigt der Tooltip den Gegenstand.
- **Wenn** du gewürfelt hast oder der Wurf zu Ende ist, **dann** bleibt die Zeile so viele Sekunden stehen, wie „Ergebnis zeigen“ sagt (Standard 3, bei 0 sofort weg), mit dem Gewinner im Balken, falls er schon feststeht, und verschwindet dann.
- **Wenn** du auf das Uhr-Symbol in der Kopfleiste oder in den Optionen auf „Beuteverlauf zeigen“ klickst, **dann** klappt auf der anderen Seite der Kopfleiste der Beuteverlauf der Sitzung auf: die letzten 15 Würfe, neueste oben, mit Symbol, Name in Qualitätsfarbe, deiner Wahl und dem Gewinner in Klassenfarbe mit Wurfzahl („Alle haben gepasst“ / „noch kein Ergebnis“). Ein Gewinner, der erst nach dem Verschwinden der Zeile feststeht, erscheint dort nachträglich. Über einem Eintrag zeigt der Tooltip den Gegenstand und alle Spieler; Shift-Klick verlinkt ihn.
- **Angenommen** „Abgerundet“ ist an (Standard), **dann** haben Zeilen und Kopfleiste runde Ecken mit dünnem Rand und das Symbol ist abgerundet wie in den Taschen, mit Ring in Qualitätsfarbe; aus: eckig wie bisher. Das Umschalten zeigt sich sofort.
- **Wenn** du die Liste an ihrer Kopfleiste ziehst, **dann** bleibt sie dort, wo du sie loslässt, auch nach `/reload` (ein Klick ohne Ziehen klappt sie ein). **Wenn** du sie im Bearbeitungsmodus verschiebst oder Breite, Höhe (Zeilenhöhe), Schriftgröße, Abstand, Wachstumsrichtung oder Balkentextur änderst, **dann** sieht man das sofort; „Testwürfe zeigen“ füllt die Liste mit Beispielen.
- **Wenn** du die Würfelliste ausschaltest, **dann** fragt ein Fenster „Jetzt neu laden?“; bis zum `/reload` arbeitet die Liste weiter (laufende Würfe lassen sich noch beantworten), danach sind die Würfelfenster des Spiels zurück. War die Liste seit dem Einloggen nie an, ist aus sofort aus.
- **Angenommen** die Gamepad-Oberfläche ist an, **dann** bleibt die Würfelliste leer und das Spiel zeigt seine eigenen Würfe.
- **Dann** steht über der Liste (bei „Nach oben“ darunter) eine Kopfleiste „Würfe (Anzahl)“ mit „-“ und einem roten X. **Wenn** du auf „-“ oder die Kopfleiste klickst, **dann** klappen die Zeilen weg und nur die Kopfleiste bleibt („+“ klappt sie wieder auf). **Wenn** du auf das X klickst, **dann** verschwindet die Liste, bis der nächste Wurf beginnt; offene Würfe laufen weiter und zählen bei Ablauf als Passen. Beides gilt bis zum nächsten Einloggen bzw. `/reload`; „Testwürfe zeigen“ öffnet die Liste wieder.
- Bekannte Grenze: Zähler, Spielerliste und Gewinner kommen aus dem Beuteverlauf des Spiels. Kennt der Verlauf einen Wurf nicht oder liegt derselbe Gegenstand zweimal in der Liste, bleiben sie leer; würfeln geht trotzdem. Läuft ein Wurf über einen Ladebildschirm, öffnet das Spiel ihn danach zusätzlich in seinem eigenen Fenster.

### F-45 Tägliches Wort
- Angenommen die Flugleiste ist an, **wenn** du fliegst, **dann** sitzt rechts neben der Leiste ein Knopf „Wort“; ein Klick öffnet „Tägliches Wort #N“ mit 6 × 5 Feldern, QWERTZ-Tastatur, „Nächstes Wort in …“ und der Statistik.
- **Wenn** du ein Wort tippst (Tastatur oder Klick) und Enter drückst, **dann** färben sich die Felder: grün richtig, gelb an anderer Stelle, grau nicht im Wort; die Tastatur färbt die Buchstaben mit. Unbekannte Wörter: „Nicht in der Wortliste.“
- **Wenn** du landest, **dann** schließt sich das Fenster; `/vfword` öffnet es wieder mit deinem Stand, auch auf einem anderen Charakter.
- Angenommen gelöst oder sechs Fehlversuche, **dann** steht „Gelöst in N.“ bzw. „Das Wort war …“, und Gespielt/Gewonnen/Serie/Beste zählen weiter; am nächsten Tag kommt ein neues Wort.

### F-46 DoT-Leisten
- Angenommen ein Klassen-Charakter mit DoTs (z. B. Hexenmeister, Priester, Schamane) und ein feindliches Ziel, **dann** steht über dem Zielrahmen pro bekanntem DoT eine Zeile mit Symbol; ist der DoT nicht auf dem Ziel, ist die Zeile grau.
- **Wenn** du den DoT wirkst, **dann** füllt sich die Leiste mit der Restzeit, das Symbol wird farbig und rechts steht die Zeit – auch im Kampf.
- **Dann** hat jeder DoT seine eigene Balkenfarbe (rot, lila, orange, blau, gelb in Zeilenreihenfolge), je Zauber unter „Verfolgte Zauber“ änderbar.
- **Wenn** du danach einen Buff bekommst, der den DoT stärker macht, **dann** wird der Balken grün und links steht z. B. „+13%“; ohne Gewinn (gleich oder schwächer) steht nichts und der Balken behält seine Farbe.
- **Wenn** du im Bearbeitungsmodus die DoT-Leisten anklickst und im Fensterpanel den Regler „Breite“ ziehst, **dann** werden die Leisten und ihr Kasten nach kurzem Loslassen so breit; derselbe Wert steht danach unter Ressourcenleisten → Dots → „Breite“.
- **Wenn** du das Ziel wechselst, **dann** zeigen die Leisten sofort die DoTs des neuen Ziels.
- **Dann** lassen sich Position (Bearbeitungsmodus), Breite, Höhe, Abstand, Textur, Farben und die verfolgten Zauber einstellen, sichtbar nach kurzer Pause.

### F-47 Fensterplätze auch im Blizzard-Layout
Verworfen am 05.11.2026: das Schreiben ins Blizzard-Layout (`C_EditMode.SaveLayouts`) hat die Gruppen- und Schlachtzugsrahmen des Clients mit unserem Taint neu aufgebaut, mit tausendfachen Fehlern. Was bleibt:
- Angenommen ein Fenster ist an Spieler- oder Zielrahmen geheftet („Fenster folgen“, z. B. die DoT-Leisten am Ziel), **wenn** du dich neu einloggst oder `/reload` machst, **dann** steht es am selben Platz am Rahmen wie vorher.
- **Wenn** du „Diesen Rahmen zurücksetzen“ drückst, **dann** geht der Rahmen an den Platz aus Blizzards Layout zurück (nicht in die Bildschirmmitte).
- **Wenn** du in einer Gruppe Blizzards Bearbeitungsmodus öffnest und schließt, auch nachdem du in unserem Rahmen verschoben hast, **dann** zeigt BugGrabber keine Fehler aus `UnitFrame.lua` oder `CompactUnitFrame.lua`.

### F-48 Berufe-Tab: Symbol über Erzen und Kräutern
- Angenommen der Charakter kann Bergbau oder Kräuterkunde und „Erze und Kräuter markieren“ ist an, **wenn** du auf ein Erzvorkommen oder Kraut zuläufst, **dann** steht schon aus größerer Entfernung (Regler „Reichweite“, Standard 40 Meter) das Spitzhacken- bzw. Kräutersymbol des Spiels darüber; mit der Interaktionstaste baust du es ab.
- **Wenn** du den Schalter ausschaltest oder ein Charakter ohne Sammelberuf eingeloggt ist, **dann** gelten wieder deine eigenen Einstellungen für weiches Anvisieren (Symbol, Reichweite).
- **Wenn** du mit der Angeltaste angelst, während der Schalter an ist, **dann** bleibt nach dem Angeln das Symbol über Erzen und Kräutern erhalten.
- **Dann** zeigt der Tab, ob der Charakter einen Sammelberuf kennt.

---

### F-49 DoT-Restzeit auf dem Symbol
- Angenommen eine Zeile mit einem DoT (z. B. Verderbnis, Schattenwort: Schmerz) und „Restzeit auf dem Ziel zeigen“ an, **wenn** du den DoT auf ein feindliches Ziel wirkst, **dann** steht mitten auf dem Symbol seine Restzeit, auch im Kampf.
- **Dann** wird die Zahl grün, sobald nur noch Wirkzeit + Vorlauf übrig sind (Sofortzauber mit Vorlauf 1: bei 1 Sekunde); vorher hat sie die Farbe der Abklingzahl der Leiste.
- **Wenn** du das Ziel wechselst, **dann** zeigt das Symbol sofort die Zeit auf dem neuen Ziel, oder nichts, wenn der DoT dort nicht läuft.
- **Wenn** du „Vorlauf in Sekunden“ oder „Farbe zum Nachwirken“ änderst, **dann** zeigt das Symbol es sofort, auch bei einem laufenden DoT.

---

### F-50 Funkeln auf dem nächsten Erz oder Kraut
- Angenommen „Erze und Kräuter markieren“ und „Funkeln auf Erz und Kräutern“ sind an und der Charakter kann Kräuterkunde, **wenn** du auf ein Kraut zuläufst, **dann** funkelt es golden (Schein, aufsteigende Funken, aufblitzende Sterne), sobald es das nächste nutzbare Objekt vor dir ist.
- Angenommen der Charakter kann nur Kräuterkunde, **wenn** du vor einer Erzader stehst, **dann** funkelt sie nicht (und umgekehrt mit Bergbau).
- **Wenn** das nächste Objekt ein Briefkasten, eine Truhe oder ein NPC ist, **dann** funkelt nichts und es erscheint keine zusätzliche Namensplakette.
- **Wenn** du weggehst oder ein anderes Objekt näher ist, **dann** verschwindet das Funkeln bzw. springt auf das neue Kraut/Erz.
- **Wenn** du die Farbe änderst, **dann** funkelt das nächste Vorkommen in der neuen Farbe.
- **Wenn** du den Schalter ausschaltest, **dann** gelten wieder deine eigenen Einstellungen für Namensplaketten von Objekten.
- Angenommen ein Controller ist angeschlossen, **dann** bleibt das Funkeln aus und es kommt kein Fehler `SetPreferredGamepadInteractTarget`.

### F-51 Freundesliste im dunklen Stil
- Angenommen die Karte „Freundesliste“ steht auf **Modern**, **wenn** du mit O das Freundesfenster öffnest, **dann** ist es fast schwarz mit dünnem Rand, ohne Porträt und Rahmenkunst; Status-Auswahl, Menü-Knopf, Suchfeld und Filter sind flach und dunkel, BattleTag und Kopier-Symbol bleiben.
- **Dann** ist jeder Freund eine flache dunkle Zeile mit feiner Trennlinie; Gruppenköpfe sind flache Streifen; Einladen- und Beschwören-Knopf sind kleine flache Quadrate; „Freund hinzufügen“ ist flach, die Scrollleiste schmal.
- **Wenn** du einen Freund anklickst, **dann** trägt seine Zeile links einen goldenen Balken; ein zweiter Klick nimmt ihn wieder weg.
- **Wenn** du suchst, filterst, eine Gruppe ein- oder ausklappst, über eine Zeile fährst oder sie rechtsklickst, **dann** funktioniert alles wie ohne Skin (Tooltip, Menü, Einladen, Kopieren, Status).
- **Wenn** du die Karte auf **Aus** stellst, **dann** sieht das offene Fenster sofort wieder aus wie das des Spiels.
- Schaltet das Spiel das neue Freundesfenster ab und zeigt die alte Freundesliste, **dann** ist auch diese dunkel (Klassenfarbe, Kopier-Knopf, flache Zeilen).

---

### F-52 Neuer Zauberrang nicht doppelt
- Angenommen ein Zauber steht mit Rang 1 auf einer Leiste, **wenn** du Rang 2 lernst, **dann** steht er in der Vorschau nur einmal (kein zweites, halb durchsichtiges Symbol mit Rang 2).
- **Dann** zeigt das „+“-Menü den Zauber mit dem Namen der Leiste dahinter; ihn dort zu wählen ersetzt die alte Zeile, statt eine zweite anzulegen.
- **Dann** zeigt das Symbol die Tastenbelegung des Aktionsleisten-Knopfs, auf dem jetzt Rang 2 liegt.

---

### F-53 Talentbedingungen pro Symbol
- **Wenn** du in der Vorschau mit der rechten Maustaste auf ein Symbol klickst, **dann** öffnet sich „Talentbedingungen“ mit deinen drei Bäumen; jeder Baum klappt seine Talente mit Symbol auf.
- **Wenn** du ein Talent anklickst, **dann** wechselt es zwischen „(mit)“ grün, „(ohne)“ rot und keiner Bedingung; das Menü bleibt offen.
- Angenommen „(mit)“ auf einem Talent, das du nicht gewählt hast, **dann** verschwindet das Symbol von der Leiste im Spiel, die Leiste rückt zusammen; in der Vorschau bleibt es halb durchsichtig stehen.
- **Wenn** du das Talent lernst oder umskillst, **dann** erscheint oder verschwindet das Symbol sofort, ohne /reload.
- **Dann** steht derselbe Eintrag auch im Linksklick-Menü des Symbols, mit der Zahl der gesetzten Bedingungen; „Talentbedingungen löschen“ nimmt alle zurück.

---

### F-54 Menge eintippen
- **Wenn** du im Teilen-Fenster (Händler mit Shift-Klick, Tasche mit Shift-Klick) auf die Zahl klickst, **dann** erscheint dort ein Eingabefeld mit der Menge markiert; der Tooltip über der Zahl sagt das.
- **Wenn** du 45 tippst und Enter drückst, **dann** kauft bzw. teilt es genau 45; tippst du mehr als möglich, springt das Feld auf die Grenze.
- **Wenn** du Escape drückst, **dann** bleibt die alte Menge; klickst du daneben, bleibt die getippte Menge stehen, ohne zu kaufen.
- **Wenn** das Fenster offen ist, aber du nicht auf die Zahl geklickt hast, **dann** laufen WASD und andere Tasten wie gewohnt.

### F-55 Bannbare Buffs am feindlichen Ziel leuchten
- **Angenommen** du spielst einen Charakter, der einem Feind Buffs nehmen kann — Magie (Priester mit Magiebannung, Schamane mit Reinigen, Hexenmeister mit Teufelsjäger) oder Wutanfälle (Jäger mit Einlullendem Schuss, Druide mit Tier besänftigen), Stil Standard oder Classic, und „Bannbare Buffs leuchten“ ist an.
- **Wenn** du einen Feind anvisierst (Monster, Tier oder gegnerischer Spieler im PvP), **dann** stehen unter dem Zielrahmen (unter den Debuffs) weiter alle seine Buffs in gewohnter Größe; die Buffs, die du mit diesem Charakter bannen kannst, stehen vorn und tragen einen warm-weißen Rahmen mit goldenem, umlaufendem Schein (dasselbe Leuchten wie ein ausgelöster Zauber auf der Aktionsleiste), alle anderen leuchten nicht.
- **Wenn** das Ziel freundlich ist, **dann** ist die Buff-Anzeige genau wie ohne das Addon (Blizzards eigene Reihe, nichts leuchtet).
- **Angenommen** du spielst einen Jäger mit Einlullendem Schuss (oder einen Druiden mit Tier besänftigen), **wenn** du einen Feind mit einem Wutanfall anvisierst, **dann** steht der Wutanfall vorn und leuchtet; bei Namensplaketten zeigt „Nur entfernbare“ ihn ebenfalls.
- **Wenn** du im Kampf das Ziel wechselst oder ein Buff ausläuft, **dann** folgt die Reihe sofort; nie stehen zwei Buff-Reihen untereinander.
- **Wenn** du die Einstellung ausschaltest oder einen Charakter ohne Bannzauber spielst, **dann** zeigt bei jedem Ziel Blizzards eigene Buff-Reihe alles wie gewohnt.

### F-56 Schlüsselbund im Taschenfenster
- **Angenommen** du hast mindestens einen Schlüssel am Schlüsselbund und „Schlüsselbund anzeigen“ ist an, **dann** steht in der Werkzeugzeile des Taschenfensters ein Schlüssel-Knopf und ganz unten im Fenster der Abschnitt „Schlüsselbund (Anzahl)“ mit deinen Schlüsseln und den freien Plätzen der angefangenen Viererreihe — in jeder Ansicht (Kategorien, alle Taschen, pro Tasche).
- **Wenn** du den Schlüssel-Knopf drückst, **dann** klappt der Abschnitt sofort ein bzw. aus; der Knopf ist golden, solange er offen ist, und der Zustand bleibt nach `/reload` erhalten.
- **Wenn** du einen Schlüssel im Abschnitt rechtsklickst, aufnimmst oder auf einen freien Platz dort legst, **dann** verhält er sich wie jeder andere Taschenplatz (auch im Kampf, ohne „Aktion blockiert“).
- **Wenn** du Blizzards Schlüsselbund-Knopf an der Taschenleiste drückst, **dann** öffnet sich unser Taschenfenster mit ausgeklapptem Schlüsselbund; ein zweiter Klick klappt ihn wieder ein.
- **Angenommen** der Schlüsselbund ist leer oder die Einstellung ist aus, **dann** gibt es weder Knopf noch Abschnitt.
- **Dann** zählen die Schlüsselbund-Plätze nicht bei den freien Taschenplätzen mit, und Sortieren, Müllverkauf und der Taschen-voll-Helfer fassen den Schlüsselbund nicht an.

### F-57 Chat-Eingabezeile in einer Schrift
- **Wenn** du Enter drückst und eine lange Zeile tippst (z. B. im Gildenchat), **dann** steht der blinkende Textcursor direkt hinter dem letzten Buchstaben, nicht ein Stück rechts davon.
- **Dann** haben der Kanalname davor („Gilde:“, „Sagen:“, „Flüstern an …:“) und der getippte Text dieselbe Schrift und dieselbe Größe; „Textgröße der Eingabezeile“ ändert beide sofort.
- **Dann** behält die Zeile die Farbe des Kanals, auch direkt nach `/reload` und nach einer Änderung in den Chat-Optionen.
- **Wenn** du das Chat-Modul ausschaltest, **dann** sieht die Eingabezeile wieder aus wie bei Blizzard.

### F-58 Chat-Links treffen genau
- **Angenommen** das Chat-Modul ist an und „Zeitstempel zeigen“ ist an, **wenn** jemand im Chat schreibt, **dann** steht vor der Zeile die Uhrzeit im gewählten Format und in der gewählten Farbe.
- **Wenn** du einen Spielernamen, einen Kanalnamen („[Gruppe]“, „[2. Handel]“) oder einen Gegenstand im Chat anklickst — an jeder Stelle des Links, auch ganz rechts, auch in einer umgebrochenen Zeile —, **dann** reagiert genau dieser Link (Flüstern öffnet sich, der Kanal wird gewählt, der Gegenstand zeigt seinen Tooltip).
- **Wenn** du Beute aufhebst oder eine Systemmeldung kommt, **dann** steht dort kein Zeitstempel; der Gegenstand in der Beutezeile ist trotzdem genau anklickbar.
- **Wenn** du Format oder Farbe änderst oder den Zeitstempel ausschaltest, **dann** gilt das für neue Zeilen; alte behalten, was sie haben.
- **Wenn** du das Chat-Modul ausschaltest, **dann** gilt wieder die Zeitstempel-Einstellung, die das Spiel vorher hatte.
- Bekannte Grenze: Zeilen aus der letzten Sitzung (nach `/reload`, grau) haben keine anklickbaren Links.

### F-59 Klassen: Priester-Bögen
- **Angenommen** du spielst einen Priester und das Modul Klassen ist an, **wenn** du dir Machtwort: Schild gibst, **dann** füllt sich rechts vom Charakter ein Bogen aus Segmenten von unten bis oben; darunter stehen die Absorption als Zahl und die Restzeit (30 s).
- **Wenn** du Schaden nimmst (auch im Kampf), **dann** gehen die Segmente von oben nach unten aus, die Zahl zählt mit, und bei leerem Schild sind Bogen und Zahl weg.
- **Wenn** der Schild unter ein Viertel fällt, **dann** wird das unterste Viertel des Bogens rot-orange; ein ganz geschluckter Treffer lässt den Bogen kurz weiß aufblitzen.
- **Wenn** du Inneres Feuer wirkst, **dann** steht links vom Charakter ein gespiegelter, orangefarbener Bogen mit allen Segmenten; jeder körperliche Treffer, der durchkommt, nimmt eine Aufladung weg (kurzes weißes Aufblitzen), außerhalb des Kampfes stimmt er mit dem Buff überein.
- **Wenn** du im Edit Mode bist oder „Vorschau zeigen“ einschaltest, **dann** sind beide Bögen voll zu sehen und lassen sich zusammen verschieben und skalieren; jede Einstellung (Segmente, Größe, Abstand, Höhe, Krümmung, Farben) zeigt sich sofort.
- **Angenommen** du spielst keine Priester-Klasse, **dann** zeigt der Tab „Priester“ den Hinweis, dass die Einstellungen nur für diese Klasse gelten, und auf dem Bildschirm erscheint nichts.
- Bekannte Grenze: Wirkst du im Kampf einen Schild auf einen anderen Spieler, nimmt der eigene Bogen dessen Größe an und die Restzeit läuft neu, bis der Kampf endet.

### F-60 Erinnerungen: „Anzeigen unter (Minuten)“ und Countdown
- **Angenommen** unter Erinnerungen → Verbrauchsgüter steht „Satt: anzeigen unter (Minuten)“ auf 10, du hast passendes Essen in den Taschen und der Essens-Buff hat noch 9 Minuten, **dann** steht das Essen golden in der Leiste und auf dem Symbol läuft die Restzeit als „8:59“ herunter; ein Klick isst neu.
- **Wenn** der Regler auf 0 steht (Standard), **dann** gilt für das Essen wie bisher „Vor dem Ablaufen warnen“.
- **Angenommen** der Lagerfeuer-Buff ist unter „Verfolgte Zauber“ an und sein Regler „anzeigen unter (Minuten)“ steht auf 5, **wenn** der Buff unter 5 Minuten fällt, **dann** erscheint sein Symbol golden mit Countdown; auf 0 (Standard) erscheint es wie bisher nur, wenn der Buff fehlt.
- **Wenn** irgendeine Erinnerung wegen „läuft bald ab“ in der Leiste steht (Buff, Waffenverzauberung, Fläschchen), **dann** zeigt auch sie den Countdown; fehlende Buffs zeigen keinen.
- **Wenn** du einen der Regler bewegst, **dann** zeigt die Vorschau über der Seite den Zustand sofort, Countdown eingeschlossen.
- Bekannte Grenze: Die Leiste schaut alle 5 Sekunden nach, ein Symbol kann also bis zu 5 Sekunden nach der Schwelle erscheinen. Essen wird in der Grundeinstellung nur in Dungeons und Schlachtzügen erinnert.

### F-61 Händlerfenster: schon Vorhandenes rot
- **Angenommen** unter Skins → Fenster-Skins → Händlerfenster ist „Gegenstände, die du schon hast, rot tönen“ an, **wenn** du bei einem Rezepthändler stehst, **dann** sind die Rezepte, die du schon kannst (Tooltip: „Bereits bekannt“), rot wie etwas, das du nicht benutzen kannst; alle anderen sehen aus wie immer.
- **Wenn** du ein Rezept kaufst und lernst, **dann** wird seine Zelle ohne Schließen des Fensters rot.
- **Wenn** du blätterst oder den Händlerfilter umstellst, **dann** stimmt die Tönung auf jeder Seite; auf dem Reiter „Rückkauf“ wird nichts getönt.
- **Wenn** du den Schalter bei offenem Händlerfenster ausschaltest, **dann** haben die Zellen sofort wieder die Farben des Spiels. Standard: aus.
- **Wenn** du danach kaufst, verkaufst oder reparierst, **dann** geht alles wie vorher und es kommt keine „Aktion blockiert“-Meldung.
- Bekannte Grenze: Was als vorhanden zählt, sagt der Tooltip des Spiels („Bereits bekannt“, bei Haustieren „Gesammelt (1/…)“). Ein Reittier, das nur als Gegenstand in der Tasche liegt, zählt nicht.
- Nicht gebaut: das Ausblenden dieser Gegenstände. Die Händlerliste gehört dem Spiel und blättert nach festen Nummern; Ausblenden ohne Lücken bräuchte eine eigene Händlerliste. Entscheidung des Spielers (2026-11-14): die Tönung reicht, kein Ausblenden.

### F-62 Reit-Schmuckstück
- **Angenommen** das Schmuckstück-Fenster ist an und unter „Reit-Schmuckstück“ ist die Karotte für den unteren Platz gewählt, **wenn** du außerhalb des Kampfes aufsitzt, **dann** liegt nach etwa einer Sekunde die Karotte im unteren Platz.
- **Wenn** du absitzt, **dann** kommt das Schmuckstück zurück, das vorher im Platz lag; war es von Hand angelegt, gilt es wieder als deine Wahl (die Warteschlange lässt es liegen).
- **Angenommen** du wirst im Kampf vom Reittier geholt, **dann** bleibt die Karotte bis zum Kampfende und wird dann getauscht.
- **Angenommen** die Karotte liegt im Platz, du sitzt nicht auf und nichts ist zum Zurücklegen gemerkt (z. B. von Hand angelegt), **dann** holt die Warteschlange des Platzes, wenn sie an ist, ihr erstes bereites Schmuckstück; ist sie aus, bleibt die Karotte.
- **Wenn** du auf dem Reittier von Hand ein anderes Schmuckstück in den Reit-Platz legst, **dann** bleibt es bis zum nächsten Aufsitzen.
- **Wenn** du auf dem Reittier `/reload` machst oder ausloggst und danach absitzt, **dann** kommt das vorherige Schmuckstück trotzdem zurück.
- **Wenn** „Kein Reit-Schmuckstück“ gewählt ist (Standard), **dann** wechselt nichts beim Auf- und Absitzen.
- Bekannte Grenze: Ein benutzbares Schmuckstück, das zurückkommt, hat die 30 Sekunden Abklingzeit des Spiels nach dem Anlegen.

### F-63 Goldprüfung: Vergleich
- **Angenommen** in der Goldprüfung wird ein Charakter angezeigt und es gibt mindestens einen weiteren gespeicherten, **wenn** du unten „Vergleichen“ klickst, **dann** öffnet sich die Spielerliste mit der Zeile „Wähle, mit wem … verglichen wird“ (ohne den angezeigten Charakter, mit Suche und Sortierung).
- **Wenn** du dort einen Charakter anklickst, **dann** stehen beide nebeneinander: links der angezeigte, rechts der gewählte, je mit Name in Klassenfarbe, Stufe, Klasse und Gilde; darunter Zeile für Zeile Urteil, Stufe, Höchststand, erklärt/unerklärt, alle Einkommensquellen, Reisen, Porto, Auktionen, Quests, Kills, Dungeons, Tode, Flugrouten, ehrenhafte Siege und letzter Scan.
- **Dann** ist bei zwei bekannten Zahlen die höhere weiß und die niedrigere gedämpft; was das Spiel nicht geliefert hat, steht als „--“ und zählt nie als 0.
- **Wenn** du dich mit jemandem vergleichen willst, **dann** klickst du erst „Mich prüfen“ und dann „Vergleichen“; für zwei andere öffnest du den ersten über „Spieler“ und wählst den zweiten über „Vergleichen“.
- **Wenn** du „Anderer Charakter“ klickst, **dann** kommt die Auswahlliste wieder; ein zweiter Klick auf „Vergleichen“ schließt die Ansicht, ein späterer öffnet sie mit demselben Partner.
- **Wenn** während des Vergleichs ein neuer Scan fertig wird, **dann** zeigt die linke Seite den neuen Charakter.
- Bekannte Grenze: Die rechte Seite ist immer der letzte gespeicherte Scan dieses Charakters, kein frischer.

### F-64 Erinnerungen: eigenes Essen wählen
- **Angenommen** die Essens-Erinnerung steht in der Leiste, **wenn** du sie rechts anklickst, **dann** öffnet sich ein Menü mit „Automatisch: zuletzt gegessen, sonst das Beste“ und allen Speisen und Getränken aus deinen Taschen, je mit Symbol und Anzahl; die aktuelle Wahl hat einen Haken.
- **Wenn** du ein Essen wählst, **dann** zeigt die Erinnerung sofort dessen Symbol und Anzahl, und ein Linksklick isst genau dieses.
- **Angenommen** das gewählte Essen ist aufgebraucht, **dann** zeigt die Erinnerung wieder das Essen der Rolle; kaufst du nach, gilt deine Wahl wieder.
- **Wenn** du „Automatisch“ wählst, **dann** gilt wieder die Reihenfolge aus F-82. Die Wahl gilt pro Charakter.
- **Dann** nennt der Tooltip der Essens-Erinnerung den Rechtsklick; ein Rechtsklick auf andere Erinnerungen tut nichts.
- Bekannte Grenze: Das Spiel führt Speisen und Getränke in einer Gruppe, im Menü stehen deshalb auch Getränke. Als satt gilt weiterhin nur ein Essens-Buff, den die Erinnerung kennt (Satt und die vier benannten); nach anderem Essen bleibt das Symbol stehen.

### F-65 Makro-Fabrik
- **Angenommen** Komfort ist an, **wenn** du unter Komfort → Makros einen Haken setzt (z. B. „Essen“), **dann** steht in der Makroliste deines Charakters ein Makro „VF Food“ (weitere: VF Drink, VF Stone, VF Heal, VF Mana, VF Soul, VF Spell, VF Fire, VF Gem); der Knopf daneben legt es auf den Mauszeiger, ein Klick auf einen Leistenplatz legt es ab.
- **Angenommen** das Makro liegt auf einer Leiste, **dann** zeigt der Knopf Symbol, Anzahl und Tooltip des besten Gegenstands seiner Art, der in den Taschen liegt und den deine Stufe erlaubt, und ein Klick benutzt ihn.
- **Wenn** du etwas Besseres kaufst, den Stapel aufbrauchst oder eine Stufe aufsteigst, **dann** wechselt der Knopf außerhalb des Kampfes von selbst auf den nun besten Gegenstand; im Kampf erst nach dem Kampf.
- **Angenommen** nichts Passendes ist mehr in den Taschen, **dann** zeigt der Knopf weiter den letzten Gegenstand mit Anzahl 0.
- **Angenommen** du hast Buff-Essen („Nahrhaftes Essen“) und gewöhnliches Essen dabei, **dann** isst „Essen“ das gewöhnliche; das Buff-Essen erst, wenn sonst nichts da ist. Dasselbe gilt für „Trinken“ und Buff-Getränke.
- **Angenommen** du bist Hexenmeister mit einem Zauberstein (Feuerstein) in den Taschen, **wenn** du „VF Spell“ („VF Fire“) drückst, **dann** liegt die Verzauberung auf der Waffenhand; ohne Stein stellt derselbe Knopf einen her.
- **Angenommen** du bist Hexenmeister ohne Gesundheitsstein (Seelenstein) bzw. Magier ohne Manaedelstein, **dann** wirkt derselbe Knopf den besten Herstellungszauber, den du kannst, und wird wieder zu „benutzen“, sobald der Stein in den Taschen liegt.
- **Dann** sieht ein Krieger oder Schurke weder „Trinken“ noch „Manatrank“, nur ein Hexenmeister „Seelenstein“, „Zauberstein“ und „Feuerstein“, nur ein Magier „Manaedelstein“.
- **Wenn** du den Haken entfernst, **dann** ist das Makro gelöscht (auch von der Leiste). Modul aus oder Profilwechsel löscht nichts.
- **Angenommen** alle 30 Charakter-Makroplätze sind belegt, **dann** meldet der Chat das einmal und es wird nichts angelegt.
- Bekannte Grenzen: Alle IDs und Effektnamen sind aus den Tabellen dieses Clients gelesen (Build 1.60.1.70938), im Spiel aber nicht ausprobiert. Offen ist vor allem, ob der Zauber- und Feuerstein nach „/use“ noch den Klick auf die Waffenhand braucht (das Makro schickt ihn mit, wie die Gift-Erinnerung) und ob „/cast Gesundheitsstein herstellen“ den höchsten Rang wirkt. Der Magier-Knopf beschwört nur, wenn gar kein Edelstein da ist.

### F-66 Gold-Tooltip: Bilanz und Charakterliste
- **Angenommen** „Gold des Tages verfolgen“ ist an, **wenn** du über die Geldzeile der Taschen fährst, **dann** ist „Bilanz“ genau „Verdient“ minus „Ausgegeben“ (grün mit Plus, rot mit Minus) und nie der ganze Geldbeutel.
- **Wenn** du dich neu einloggst oder `/reload` machst, **dann** bleiben Verdient, Ausgegeben und Bilanz stehen; der erste Login eines neuen Kalendertages beginnt bei null.
- **Angenommen** du loggst auf einen anderen Charakter ein und bewegst kein Geld, **wenn** du zurückwechselst und den Tooltip öffnest, **dann** steht dieser Charakter mit seinem echten Geldbetrag in der Liste, und „Gesamt“ zählt ihn mit.
- **Angenommen** der Client meldet den Realm-Namen leer (seit Ende Nov. 2026), **wenn** du den Tooltip öffnest, **dann** steht jeder Charakter genau einmal als „Name - Realm“, mit seinem neuesten Betrag; die alten Einträge „Name -“ ohne Realm sind weg (Migration 4), „Gesamt“ zählt jeden nur einmal. Dasselbe gilt für die eigenen Charaktere im Postfenster.
- Bekannte Grenze: Das Spiel gibt einem Addon nur den Geldbeutel des eingeloggten Charakters. Ein Charakter erscheint in der Liste, sobald er einmal mit dem Addon (Taschen-Modul an) eingeloggt war, und zeigt den Stand seines letzten Logins.

### F-67 Handwerkstaschen als eigene Abschnitte
- **Angenommen** du trägst eine Handwerkstasche (Reagenzientasche im eigenen Platz, Kräuter-, Verzauberer-, Bergbautasche, Köcher, Seelentasche) und „Handwerkstaschen als eigene Abschnitte“ ist an, **wenn** du das Taschenfenster in der Kategorien-Ansicht oder in „Alle Taschen“ öffnest, **dann** stehen ihre Plätze nicht mehr in den Kategorien, nicht unter „Frei“ und nicht im großen Block, sondern darunter als eigener Abschnitt „Taschenname (frei/gesamt)“: volle und freie Plätze nebeneinander in Platzreihenfolge, über dem Schlüsselbund.
- **Dann** tragen die Plätze dort dieselben Farben und Rahmen wie überall (Familienfarbe der Tasche, Qualitätsring), und das Fenster ist so breit wie vorher.
- **Wenn** du den Taschen-Knopf in der Werkzeugzeile drückst (Symbol der Handwerkstasche), **dann** klappen die Abschnitte sofort ein bzw. aus; der Knopf ist golden, solange sie offen sind, und der Zustand bleibt nach `/reload`.
- **Angenommen** die Abschnitte sind eingeklappt, **wenn** du etwas ins Suchfeld tippst, **dann** sind sie für die Dauer der Suche sichtbar, Treffer darin eingeschlossen.
- **Wenn** du die Einstellung ausschaltest, **dann** liegen die Gegenstände sofort wieder in den Kategorien und der Knopf ist weg. Ohne Handwerkstasche gibt es weder Knopf noch Abschnitt.
- **Dann** bleiben „Pro Tasche“ und das Bankfenster unverändert; Sortieren, die Zahl freier Plätze in der Kopfzeile und der Taschen-voll-Helfer rechnen wie bisher.

### F-68 Chat-Verlauf je Reiter
- **Angenommen** „Letzte Zeilen über ein Neuladen retten“ ist an und du hast einen eigenen Reiter für Flüstern (z. B. „DMs“), **wenn** du dort Flüsternachrichten bekommst oder schreibst und dann neu einloggst oder `/reload` machst, **dann** stehen diese Zeilen grau unter „--- vorherige Sitzung ---“ wieder in genau diesem Reiter, darunter „--- diese Sitzung ---“ und die neuen Zeilen.
- **Dann** bekommt jeder Reiter nur seine eigenen Zeilen zurück; eine Zeile, die zwei Reiter gezeigt haben, steht in beiden.
- **Angenommen** im Handelschat laufen nach dem Flüstern hunderte Zeilen durch, **dann** sind die Flüsternachrichten im eigenen Reiter nach dem Relog trotzdem da: „Wie viele Zeilen je Reiter“ zählt für jeden Reiter einzeln.
- **Wenn** du danach eine Chat-Einstellung änderst, **dann** bleiben die zurückgeholten Zeilen stehen.
- **Wenn** du „Gespeicherte Zeilen vergessen“ drückst, **dann** sind sie sofort aus allen Reitern weg.
- Bekannte Grenzen: Battle.net-Flüstern und alles aus Instanzen, Raids und Schlachtfeldern wird nie gespeichert; Links in zurückgeholten Zeilen sind Text. Ein umbenannter Reiter beginnt mit leerem Verlauf. Zeilen aus der Zeit vor diesem Umbau stehen einmalig noch im ersten Reiter.

### F-70 Name in alter Chat-Zeile anklicken
- **Angenommen** „Letzte Zeilen über ein Neuladen retten“ ist an und in einem Reiter stehen nach `/reload` graue Zeilen der vorherigen Sitzung, **wenn** du dort mit links auf einen Spielernamen in eckigen Klammern klickst (z. B. `[Abunazir Jr]` in „… flüstert:“ oder „Zu …:“), **dann** öffnet sich die Eingabezeile mit einem Flüstern an genau diesen Spieler.
- **Wenn** du neben den Namen klickst (Zeitstempel, Text, leere Fläche), **dann** passiert nichts.
- **Dann** verhalten sich Namen und Links in den Zeilen der laufenden Sitzung (unter „--- diese Sitzung ---“) wie bisher, auch mit Shift und Rechtsklick.
- **Wenn** ein anderes Fenster über dem Chat liegt, du die Maus beim Klick ziehst oder Shift/Strg/Alt hältst, **dann** öffnet sich kein Flüstern.
- **Angenommen** der Spieler ist offline, **dann** öffnet sich die Eingabezeile trotzdem; ob er da ist, sagt erst das Spiel beim Abschicken.
- Bekannte Grenzen: nur Linksklick, kein Rechtsklick-Menü; Gegenstands- und andere Links in alten Zeilen bleiben Text; die Maus zeigt über dem Namen keine Hand.

### F-69 Fenster des Spiels verschieben
- **Angenommen** „Fenster des Spiels verschieben“ ist an, **wenn** du ein Fenster des Spiels (Charakter, Zauberbuch/Talente, Berufe, Karte, Händler, Post, Handel, Auktionshaus, Lehrer, Freunde, Gilde, Sammlungen, Erfolge, Kalender, Betrachten, Anprobe, Makros, Addon-Liste u. a.) an der Titelleiste mit der linken Maustaste ziehst, **dann** folgt es der Maus und bleibt beim Loslassen dort stehen; es lässt sich nicht aus dem Bildschirm schieben.
- **Wenn** du das Fenster schließt und wieder öffnest, ein zweites Fenster daneben öffnest oder schließt, oder `/reload` machst, **dann** steht es wieder an deinem Platz.
- **Dann** funktionieren Schließen-Knopf, Minimieren/Maximieren und alles im Fenster wie vorher; beim Erfolgsfenster ist die Punkte-Plakette über dem Fenster der Griff.
- **Angenommen** du bist im Kampf, **wenn** du ein geschütztes Fenster ziehen willst oder es sich öffnet, **dann** passiert kein Fehler („Aktion blockiert“): Es lässt sich nicht ziehen und steht an Blizzards Platz, nach dem Kampf wieder an deinem.
- **Angenommen** die Weltkarte ist maximiert, **dann** bleibt sie unberührt; verkleinert steht sie an deinem Platz.
- **Wenn** du „Fensterpositionen zurücksetzen“ drückst, **dann** steht im Chat die Bestätigung, und jedes Fenster ist beim nächsten Öffnen wieder an Blizzards Platz. Schaltest du die Einstellung aus, gilt dasselbe, die gemerkten Plätze bleiben aber gespeichert.
- Bekannte Grenzen: nicht verschiebbar sind Beutefenster (Edit Mode), Spielmenü, Einstellungen, Vollbild-Szenen und das Lesefenster der Post (hängt am Postfenster). Welche Fenster im Kampf als geschützt gelten, entscheidet das Spiel.

## Offen

- 2026-11-13 (Namensplaketten): fix built, NOT confirmed. Three screenshots
  -- a solid white block around the target's bar, debuff icons standing 14
  pixels apart, debuff icons with a four-pixel black frame -- "sometimes",
  no Lua error. All three are one fault: sizes meant as "n physical pixels"
  were computed from a live `GetEffectiveScale` inside the nameplate tree,
  and that scale is tiny for a moment (inferred from the pictures: two of
  them give the same factor, about 0.0145; never measured -- `/vfnpsnap`
  gets no geometry out of a plate, every rect comes back unreadable). The
  white block was our own target border, 46 pixels thick. Now every such
  size comes from `NP.Pixel`, which no longer measures. To confirm: play a
  few sessions; none of the three pictures may come back.

- 2026-11-05 (F-09): `PurchaseBankTab()` forbidden came back. The return
  channel has logged a `taint` note "bagsShown … after bag toggle" in EVERY
  session since 2026-10-07, so the fixes did not hold. Mechanism (client
  source): `ContainerFrameSettingsManager:GetBagsShown()` refills the cache
  only after a `MarkBagsShownDirty()`, and whoever reads it first writes it.
  Under the park the client's bags never become visible, so their
  OnShow/OnHide never dirty the cache securely and one tainted write stays
  for the whole session. Candidates for the tainted first read:
  `UpdateContainerFrameAnchors` via `UIParent_ManageFramePositions`,
  triggered synchronously from our code (CVar or bar or Edit Mode calls).
  Stash instead of park is on HOLD: every secure client open already runs
  `ContainerFrame_GenerateFrame` (dirty, then `UpdateContainerFrameAnchors`
  rebuilding the cache securely), even under the park. That makes a lasting
  taint through a missing heal unlikely, and the writer is still unknown.
  Follow-up error the same day: right-click on a bag item gives
  `ADDON_ACTION_FORBIDDEN UNKNOWN()` from `UseContainerItem`. Same cause,
  very likely: `ContainerFrameItemButton_OnClick` reads
  `BankFrame:GetActiveBankType()`, which returns `BankPanel.bankType`. The
  tainted bank open (its `SetTab`) wrote that field, so every item use that
  needs a protected action fails for the rest of the session. We do not touch
  `BankPanel` anywhere. `/reload` clears it.
  Next step: `/console taintLog 1`, get the error at the banker, then read
  `Logs/taint.log` on the PC (it names the variable and the file:line that
  wrote it).
  2026-11-20: the note came back under 0.25.0 (session 480). New lead from
  the client source, NOT measured: `UpdateContainerFrameAnchors` starts with
  `GetContainerScale` -> `EditModeUtil:GetRightActionBarWidth`, which asks
  `MultiBarLeft` / `MultiBarRight` (when visible) `IsInitialized()` and
  `IsInDefaultPosition()` -- both read `bar.systemInfo`. If that field is
  tainted, every rebuild of `bagsShown` runs tainted, the secure ones
  included, which fits "every session" and explains why no change in the bag
  code ever helped. Also: `ManageFramePositions` ends in
  `UpdateContainerFrameAnchors` and is reached through a plain `SetAttribute`,
  so it carries the caller's taint. `Bags.CheckTaint` now adds a second note
  ("bars read before the bag list: ...") naming which bar is visible and which
  of those fields is tainted by whom. Read it from the return channel after
  the next session with a bag toggle.
  Measured the same evening (sessions 483-488): the bar fields are clean, so
  that lead was wrong. The call stack of the first tainted rebuild is a plain
  click on a bag button with only client files in it, and the scan shows
  nothing tainted BEFORE that run -- everything it wrote is tainted, from
  `isUsingCombinedBags` on. So the run reads something tainted that is not a
  field: the list behind `ContainerFrameUtil_EnumerateContainerFrames`, which
  the client builds on the first call and keeps. `Modules/QoL/Junk.lua` made
  that first call at every login (since 2026-10-03, the day before the first
  bank error). FIX BUILT, not confirmed: the junk mark walks the frames by
  name, `check.js` refuses the call.
  Session 490 (35 minutes, first one on the fix): "bag list clean after bag
  toggle", no tainted anchor pass, no error -- the list is the client's own
  again. Still to confirm by the player: a bank tab purchase and a right-click
  item use after a bank visit. `Bags.TraceAnchors` stays as the guard: any
  tainted rebuild is noted with its call stack and a scan of what is tainted.
  The error only comes while the free first bank tab is still unbought; after
  buying it with the buy button in our bank window it stops.
  2026-11-06: cause found in the client source (Camelot BankFrame.lua): the
  frame's OnShow -> SetTab -> PurchaseFirstSlot buys the free tab and writes
  `BankPanel.bankType`, which `GetActiveBankType` in the item click reads.
  The park left that OnShow running. Fix: the frame is retired (scripts nil,
  hidden parent; concepts.md, Bags). Waiting for the in-game check; the
  taint log is now only needed for the party frames.

- 2026-11-05: Blizzard party frames run tainted after a setting change in
  the client's Edit Mode. Bug grabber, session 7: dragging a party frame
  slider (MinimalSlider -> EditModeDialogs OnSettingValueChanged ->
  UpdateSystemSettingFrameHeight -> CompactRaidFrameContainer:ApplyMultipleToFrames
  -> CompactUnitFrame_UpdateAll) is already tainted by us when
  `CompactUnitFrame_UpdateHealthColor` compares the secret bar colour (3x).
  In that tainted run `CompactUnitFrame_CheckNeedsUpdate` sets the OnUpdate
  script, so every later `CompactUnitFrame_UpdateHealPrediction` runs
  tainted too (202x, `maxHealth` compare) until `/reload`. The value we
  wrote that the chain reads is unknown: no code of ours names a compact
  frame, the Edit Mode dialog or `RAID_CLASS_COLORS` (write removed
  2026-08-11). Same next step as F-09: change the slider with
  `/console taintLog 1` and read `Logs/taint.log`.

- 2026-10-09: schwarzer Balken links an der Namensplakette des Ziels, nach dem
  Schrifttest (`/vfdiag fonts`) und den Kopierfenster-Umbauten; nach einem
  Neustart des Clients weg. Ursache unbekannt. Taucht er wieder auf: Maus
  drauf, `/vfdiag mouse`, `/reload`, dann Rückkanal lesen.
- 2026-11-10: Textcursor der Chat-Eingabezeile stand bei einer langen Zeile
  rund ein Fünftel zu weit rechts, der Kanalname war größer als der Text
  (F-57). Vermutete Ursache, im Spiel nicht gemessen: SetFont auf dem Feld
  über dem Schriftobjekt des Clients. Bleibt der Cursor falsch, liegt es
  woanders -- dann `/vfdiag fonts` und die Zeile im Rückkanal ansehen.
- 2026-11-16: „Bilanz“ im Gold-Tooltip zeigte den ganzen Geldbeutel statt
  Verdient minus Ausgegeben (F-66). Ursache: Der Tag begann bei ADDON_LOADED
  mit einem Geldbeutel von 0. Behoben, im Spiel noch zu bestätigen.
- 2026-11-20: Flüsternachrichten aus einem eigenen Reiter waren nach dem
  Relog weg (F-68). Ursache: ein gemeinsamer Verlauf für alle Reiter, nur in
  den ersten zurückgeschrieben. Umgebaut auf einen Verlauf je Reiter, im
  Spiel noch zu bestätigen.
