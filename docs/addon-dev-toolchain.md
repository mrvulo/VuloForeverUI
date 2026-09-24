# Werkzeuge und Quellen fuer die Entwicklung

Stand 2026-09-21. Was es ausserhalb dieses Repos gibt, was davon fuer Forever
1.60.1 taugt, und was wir davon uebernehmen sollten.

## Ground truth: Client-Quellen

| Quelle | Was drin ist | Wofuer |
| --- | --- | --- |
| `Gethe/wow-ui-source`, Branch `forever` | komplettes FrameXML/Camelot des 1.60.1-Clients | bisherige Referenz, bleibt die Wahrheit fuer Code |
| `Ketho/BlizzardInterfaceResources`, Branch `forever` | generierte Listen: `Templates.lua` (4046 Zeilen: Templatename -> Typ, Mixin, Inherits), `Mixins.lua`, `Frames.lua`, `Events.lua`, `CVars.lua`, `GlobalAPI.lua`, `WidgetAPI.lua`, `ScriptObjectAPI.lua`, `LuaEnum.lua`, `AtlasInfo.lua`, `GlobalStrings/` | schneller als Grep durch FrameXML, wenn die Frage lautet "gibt es das Template / das Event / die CVar ueberhaupt" |
| `Ketho/vscode-wow-api` | LuaLS-Annotationen fuer API, Widgets, Events, CVars, Enums, GlobalStrings | Editor-Vervollstaendigung; Branches bisher mainline 12.0.1, Mist 5.5.3, Vanilla 1.15.8 — **kein** Forever-Branch, also nur als Naeherung ueber mainline |

Regel bleibt: **vor einer Annahme in die Clientquelle schauen**, nicht ins
Gedaechtnis. Die Ressourcenlisten sind Index, kein Ersatz fuer den Quelltext.

## Secret Values: ein Linter existiert

`Booyaka101/wow-secret-lint` — statische Analyse fuer genau unsere Regel 2.
21 Regeln (WSL001-WSL021), verfolgt Taint-Quellen durch lokale Variablen,
Tabellenfelder, Rueckgaben und Parameter innerhalb einer Datei, und erkennt
Guards (`issecretvalue`, `canaccessvalue` sowie eigene Wrapper). Basis ist ein
eingebetteter Schnappschuss der generierten Blizzard-Doku (12.1.5, Build 69594,
10250 Funktionen mit Secret-Markern): 20 unbedingte Secret-Quellen, 314 bedingte
(`SecretWhen*`), dazu die 12.1-Auren und die geschuetzten Cooldown-Methoden.

**Eingebaut seit 2026-09-21.** `check.js` ruft als letzten Durchgang
`tools/secretlint.js` auf; der Aufruf von Hand:

```bash
node tools/secretlint.js                   # nur Neues seit der Baseline
node tools/secretlint.js --all             # alles, Baseline ignoriert
node tools/secretlint.js --write-baseline  # den aktuellen Stand annehmen
```

Vier Dinge musste der Wrapper geradebiegen:

1. **Der Client wird nicht erkannt.** `## Interface: 16001` liest der Linter als
   Classic, und Classic hat keine Secret Values — er meldet „none targeting
   retail; nothing to check" und geht mit 0 raus. Auch `--game=retail` hilft
   nicht, solange er den Ordner ueber die .toc einliest. Der Wrapper liest die
   Dateiliste deshalb selbst aus der .toc und uebergibt die Dateien einzeln.
2. **Guards.** `--secret-guard=IsSecret,ns.IsSecret` und
   `--access-guard=CanRead,ns.CanRead,Num,ns.Num` machen unsere Wrapper aus
   `Core/Secret.lua` bekannt. Ohne sie ist jede korrekt abgesicherte Stelle ein
   Treffer.
3. **Warnungen aendern den Exit-Code nicht.** Genau das, worauf es ankommt — ein
   Wahrheitstest oder ein Vergleich auf einem moeglicherweise geheimen Wert —
   ist als Warnung eingestuft. `--max-warnings=0` macht daraus ein Nein.
4. **Die Baseline merkt sich Pfade.** Ein Lauf aus `tools/` und einer aus der
   Wurzel schreiben denselben Fund unter zwei Namen. Der Wrapper startet den
   Linter deshalb immer mit der Addonwurzel als Arbeitsverzeichnis.

In der Baseline stehen vier Eintraege ueber zehn Funde, alle geprueft: die beiden
Auren-Sonden in `Core/Secret.lua` sind der Messpunkt von `/vfsecrets` und
absichtlich in `pcall` gewickelt, und die `coords` aus `CLASS_ICON_TCOORDS` sind
ein gewoehnlicher Tabellenzugriff hinter einem `ns.CanRead`-Gatter, dem der
Linter den Taint nur nicht abgewoehnen kann.

Einschraenkung: die Doku-Basis ist **retail 12.1.5**, nicht 1.60.1 — und genau
dort weicht der Forever-Client ab (siehe `docs/forever-client-research.md`:
`UnitPower("player")` ist immer secret, Auren **werfen** statt secret
zurueckzugeben). Also zweite Meinung neben `check.js` und `/vfsecrets`, nie
alleinige Wahrheit.

Der erste Lauf hat drei echte Fehler gefunden, alle drei behoben:

- `Modules/UnitFrames/Engine.lua`: `if color and color.GetRGB` auf dem Rueckgabe-
  wert von `UnitHealthPercent` — ein Wahrheitstest auf einem geheimen Wert, also
  ein Absturz. Ersetzt durch dasselbe Muster wie im Execute-Glow der Namensplaketten.
- `Engine.lua` und `Modules/UnitFrames/Extras.lua`: `token and ns.CanRead(token)`
  — das Gatter stand hinter dem Wahrheitstest, den es verhindern soll. Reihen-
  folge gedreht. Dieselbe Funktion eine Datei weiter oben hatte es richtig, mit
  Kommentar; das ist genau die Sorte Fehler, die ein Mensch beim Lesen ueberliest.

## API-Existenz: Regeln 1 und 7 als Pruefung

**Eingebaut seit 2026-09-23.** `tools/apilint.js` laeuft in `check.js` als
Abschnitt `== API existence (forever <sha>) ==` vor den Secret Values. Er liest
Core/, UI/ und Modules/ mit luaparse (lokale Namen, Parameter und Upvalues
zaehlen nicht als global) und meldet: globale Namen, `_G.X` und `_G["X"]`, die es
auf 1.60.1 nicht gibt, unbekannte `C_`-Namespaces und -Funktionen, unbekannte
`Enum.X.Y`, Eventnamen in `RegisterEvent`/`RegisterUnitEvent`/`UnregisterEvent`/
eigenen `*Event*`-Aufrufen und in `event == "..."`, die nicht in `Events.lua`
stehen, sowie `hooksecurefunc("Name")` auf fehlende Globale. Eigene Kategorien:
`deprecated` (existiert nur ueber einen Deprecation-Shim, faellt mit
`loadDeprecationFallbacks 0` weg) und `removed` (die Client-UI setzt es vor den
Addons auf nil, z.B. `loadstring_untainted`).

Datenbasis ist ein eingecheckter Schnappschuss `tools/forever-api.json`, auf je
einen Commit gepinnt: Ketho `forever` (GlobalAPI, FrameXML, Frames, Mixins,
LuaEnum, Events, GlobalStrings/enUS) plus die Globalen, die das FrameXML aus
Gethe `forever` selbst anlegt (SlashCmdList, RAID_CLASS_COLORS, Minimap, ...).
Dafuer werden die TOCs so aufgeloest wie der Client fuer `camelot`: Classic-
Dateien, Glue-Dateien und die Lua-Seite der Secure-Environment-Addons zaehlen
nicht. Der normale Lauf ist offline.

Gelesene Stellen, die schon abgesichert sind (`if X then`, `X and ...`,
`X or ...`, `type(X)`, `pcall(X)`, `if not X then return end`, `local f = X`
mit spaeterem Test auf `f`), sind „guarded": sie werden gezaehlt, scheitern aber
nie. Die Heuristik ist syntaktisch; ihre Grenzen stehen im Kopf von `apilint.js`.

```bash
node tools/apilint.js                   # nur Neues seit der Baseline
node tools/apilint.js --all --guarded   # alles, auch die abgesicherten Stellen
node tools/apilint.js --update          # neuer Build: Schnappschuss neu ziehen
node tools/apilint.js --write-baseline  # den aktuellen Stand annehmen
```

`--update` holt beide Branch-Heads (oder `--sha=` / `--ui-sha=`) und gibt den
Unterschied zum alten Schnappschuss aus: hinzugekommene und entfallene Globale,
Namespace-Funktionen, Enums und Events — das API-Changelog zwischen zwei Builds.
Die Baseline `tools/apilint-baseline.json` merkt sich Datei + Art + Name, keine
Zeilen; sie ist leer und soll es bleiben.

## Laufzeit ausserhalb des Clients

- `Meorawr/elune` — Lua 5.1 mit Blizzards Taint-Modell im Interpreter. Fremder
  Code taintet Werte, sicherer Code der taintet liest gibt Taint weiter, und
  Funktionen koennen den Taint abfragen. Ausdruecklich **keine** binaerkompatible
  Nachbildung und kein Secret-Value-Modell. Taugt fuer Taint-Tests in CI.
- `wowless/wowless` — kopfloser Interpreter fuer Client-Lua und FrameXML, laeuft
  Addons in Docker (`bin/run.sh wow --addondir <Addon>`), nutzt elune. Pre-Alpha
  und retail-orientiert; fuer uns hoechstens interessant, sobald Forever-FrameXML
  darin laeuft.

## Paketierung

`BigWigsMods/packager` PR #202 ist am 2026-09-17 gemergt: Forever wird erkannt
ueber das Versionsmuster `1.6x` (fuenfstellig `16xxx`). Ein TOC-Suffix fuer
Forever wurde bewusst **wieder entfernt**, weil Blizzard die Spezifikation noch
nicht bestaetigt hat. Fuer uns heisst das: eine einzelne `VuloForeverUI.toc` mit
`## Interface: 16001` ist weiterhin richtig, kein `-Forever.toc` erfinden.

## MCP

`RdyGaming/hated-wow-mcp` — MCP-Server mit 20 Werkzeugen: API- und Event-Suche
(~6300 Funktionen, 1700+ Events), Client-Vergleich, Template- und Mixin-Suche,
CVars, Dateisuche in 4036 FrameXML-Dateien, dazu FileDataID- und Atlas-Suche
ueber 172175 Interface-Dateien, sowie Lua-Lint, XML- und TOC-Pruefung.

```bash
claude mcp add wow -- npx -y hated-wow-mcp
npx -y hated-wow-mcp sync all
```

Die Atlas- und FileDataID-Suche ist der Teil, den wir sonst nirgends haben; sie
ist fuer die Classic-Optik der Module direkt nuetzlich.

## Fremde Messungen zu Forever

`imperial64/forever-addon-dev` fuehrt 21 am lebenden Client gemessene
Beschraenkungen. Deckt sich mit unseren eigenen Messungen und bestaetigt sie:
`UseAction`, `ReloadUI`, `SetBinding`, `SetOverrideBindingClick` sind
undokumentiert stark eingeschraenkt; die Registrierung auf Kampflog-Ereignisse
liefert `ADDON_ACTION_FORBIDDEN`; Zauberleisten und Bedrohungs**zustand** bleiben
lesbar, Bedrohungs**werte** sind secret; `UnitPower` ist entgegen der Doku immer
secret; gedrosselte Auktionsabfragen liefern leere Ergebnisse statt eines
Fehlers.

Fremdmeldungen an anderen Addons zeigen dieselben drei Klassen von Abstuerzen,
die unsere Regel 2 verhindern soll: Vergleich auf `startTime` aus
`GetSpellCooldown`, Wahrheitstest auf `isFullUpdate` aus `UNIT_AURA`, und das
Iterieren der Auren-Nutzlast. Der dort vorgeschlagene Ausweg, alles in `pcall`
zu wickeln, ist nur die halbe Wahrheit: Secret-Fehler sind echte Lua-Fehler und
werden gefangen, ein geblockter geschuetzter Aufruf loest dagegen gar keinen
Fehler aus und `pcall` meldet Erfolg.

## Nachschlagen im Netz

Keine dieser Quellen kennt Forever als eigenen Client. Sie beschreiben Retail
(oder Classic); wo sie von der Client-Quelle, dem API-Pruefer oder `/vfsecrets`
abweichen, gewinnen diese. Stand 2026-09-24.

- [Warcraft Wiki](https://warcraft.wiki.gg/wiki/Warcraft_Wiki:Interface_customization)
  -- das beste Nachschlagewerk fuer die Retail-API, zu der Forever gehoert.
  Besonders die Seiten zu Secret Values und zu den API-Aenderungen je Patch.
  Beschreibt 12.x, nicht 1.60.1.
- [Townlong-Yak FrameXML](https://www.townlong-yak.com/framexml/live) -- Viewer und
  Differ fuer FrameXML. Fuehrt Retail, Classic und Anniversary, **keinen
  Forever-Build** (geprueft 2026-09-24). Gut fuer "wie sieht das in Retail aus",
  fuer Forever-Code bleibt Gethe `forever` die Quelle.
- [Blizzard API Documentation](https://townlong-yak.com/bad/) -- die generierte
  Doku, durchsuchbar, fuer Retail. Dieselben Dateien aus dem Forever-Build liegen
  bei Gethe unter `Blizzard_APIDocumentationGenerated/`.
- [WoWUIBugs](https://github.com/Stanzilla/WoWUIBugs/issues/) -- der Bug-Tracker
  der Szene, Blizzard liest mit. Vor langer Fehlersuche nachsehen, ob es ein
  Client-Fehler ist. Fuer Forever-eigene Fehler ist der WoWUIDev-Discord
  schneller (siehe die Recherche).
- [wago.tools](https://wago.tools/) -- Datei-IDs, Listfiles, DB2-Tabellen: ob eine
  Textur oder ein Atlas im Client liegt, bevor Code darauf baut.
- [UI Add-On Development Policy](https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534)
  -- was Addons duerfen. Vor Automatik-Funktionen (Verkaufen, Annehmen, Posten)
  lesen.

Bewusst nicht aufgenommen: WoWProgramming (API ueber zehn Jahre alt), Townlong-Yak
Globe (prueft gegen Retail oder Classic; `tools/apilint.js` prueft gegen Forever),
die Packager-Anleitung (umgesetzt in `release.yml` und `.pkgmeta`), Lua-Grundlagen
(der Client laeuft Lua 5.1, die Online-Fassung von PIL beschreibt 5.0).
