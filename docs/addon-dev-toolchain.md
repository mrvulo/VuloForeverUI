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
