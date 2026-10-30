# CC-Tuersteuerung

Tuersteuerung fuer **CC:Tweaked** (Minecraft, ATM10 / 1.21.x) mit Berechtigungspruefung per Player Detector, drei Monitoren und optionalem Motor.

> **Status:** Im Spiel getestet (ATM10 / 1.21.x).

## Funktionen

- **Zugang per Whitelist:** Ein Touch-Button prueft, ob ein Whitelist-Spieler in Reichweite des Detektors steht. Rueckmeldung gruen (erteilt, mit Name) oder rot (verweigert).
- **Freie Seite:** Die Tuer oeffnet automatisch fuer jeden erkannten Spieler.
- **Innen-Taster:** Ein eigener Monitor mit einem Button "TUER AUF", ohne Pruefung.
- **Steuer-Monitor:** Anzeige und Bedienung von Modus, Tuerzustand, Motor und Zugriffslog.
- **Modi:** `Automatik`, `Gesperrt` (Tuer bleibt zu, Taster und Auto-Oeffnen aus), `Dauerauf`.
- **Motor:** Electric Motor (Create Crafts & Additions) per AN/AUS, RPM einstellbar, feste Drehrichtung.
- **Schliess-Sperre:** Die Tuer schliesst nicht, solange ein Spieler im Halte-Radius eines Detektors steht.
- **Persistenz:** Modus, Motorzustand und alle Einstellungen bleiben nach einem Neustart erhalten.
- **Monitor-Layout:** Textgroesse wird automatisch an die Monitorgroesse angepasst.

## Aufbau

| Bauteil | Aufgabe |
|---|---|
| Computer | fuehrt `door.lua` aus, Menue am Terminal |
| Redstone Relay | Ausgang zur Tuer (standardmaessig alle 6 Seiten) |
| Player Detector "Freie Seite" | oeffnet automatisch fuer jeden |
| Player Detector "Whitelist-Seite" | Berechtigungspruefung per Button |
| Monitor "Entsperren" | Whitelist-Button |
| Monitor "Tuer auf" | Taster ohne Pruefung |
| Monitor "Steuerung" | Modus, Motor, Status, Log |
| Electric Motor | per Wired Modem angeschlossen |

Alle Peripherals haengen ueber **Wired Modems** im selben Netzwerk am Computer.

Benoetigte Mods: CC:Tweaked, Advanced Peripherals (Player Detector), Create Crafts & Additions (Electric Motor).

## Installation

Auf dem Computer im Spiel:

```
wget https://raw.githubusercontent.com/ItIsYe/CC-Tuersteuerung/main/door.lua startup.lua
reboot
```

(Falls der Download blockiert ist, `door.lua` per Pastebin oder Diskette uebertragen.)

**Aktualisieren:** Datei loeschen und neu laden. Einstellungen und Whitelist bleiben erhalten, weil sie in eigenen Dateien liegen.

```
delete startup.lua
wget https://raw.githubusercontent.com/ItIsYe/CC-Tuersteuerung/main/door.lua startup.lua
reboot
```

## Ersteinrichtung

Beim ersten Start fuehrt ein Assistent in **2 Schritten** durch die Zuordnung. Jede Frage steht einzeln auf dem Bildschirm, mit Erklaerung, wofuer das Geraet gebraucht wird.

**Schritt 1 - Monitore:** Alle Monitore zeigen blau ihre Nummer (#1, #2 ...). Du gibst fuer jeden an, welche Nummer er hat:

| Monitor | Aufgabe |
|---|---|
| ENTSPERREN | Button der Whitelist-Seite, prueft die Berechtigung |
| TUER AUF | Innen-Taster, oeffnet ohne Pruefung |
| STEUERUNG | Modus, Motor, Status und Zugriffslog |

Ein Monitor kann nur einmal vergeben werden. Zugeordnete Monitore zeigen danach gruen ihre Bezeichnung.

**Schritt 2 - Detektoren:** Zu jedem Detektor steht in `[ ]`, welche Spieler er im Umkreis von 6 Bloecken sieht.

| Detektor | Aufgabe |
|---|---|
| FREIE SEITE | Seite ohne Whitelist, oeffnet automatisch fuer jeden |
| WHITELIST-SEITE | Seite mit Whitelist, gehoert zum Button ENTSPERREN |

Stell dich direkt neben den Detektor einer Seite und druecke `r`. Steht dein Name hinter einem Detektor, ist das der richtige.

Relay und Motor werden automatisch gefunden. Danach pflegst du alles ueber das Terminal-Menue.

## Terminal-Menue

| Punkt | Inhalt |
|---|---|
| 1 | Whitelist verwalten (`add <name>`, `remove <name>`) |
| 2 | Detektoren zuweisen (Freie Seite / Whitelist-Seite) |
| 3 | Monitore zuweisen (Entsperren / Tuer auf / Steuerung) |
| 4 | Motor-RPM (1-256) |
| 5 | Zeiten und Reichweiten (Offenzeit, Radien, Halte-Radius, Rueckmeldung) |
| 6 | Relay-Seiten und Invertierung |
| 7 | Auto-Oeffnen auch auf der Whitelist-Seite (fuer Whitelist-Spieler) |
| 8 | Diagnose: zeigt live, welche Spieler jeder Detektor sieht |

## Standardwerte

Alle Werte lassen sich im Terminal-Menue aendern.

| Einstellung | Standard |
|---|---|
| Tuer offen nach letzter Erkennung | 5 Sekunden |
| Reichweite Freie Seite | 4 Bloecke |
| Reichweite Whitelist-Seite | 3 Bloecke |
| Halte-Radius (Tuer schliesst nicht) | 2 Bloecke |
| Rueckmeldung auf dem Entsperren-Monitor | 3 Sekunden |
| Motor-Drehzahl | 32 RPM |
| Relay-Seiten | alle 6, Signal AN = Tuer offen |
| Auto-Oeffnen Whitelist-Seite | aus |

## Funktionsweise

- **Button-Zugang:** Beim Druck auf "Entsperren" liest das Programm die Spieler im Radius des Whitelist-Detektors. Ein Touch-Monitor liefert keinen Spielernamen, deshalb gilt: ist mindestens ein Whitelist-Spieler in Reichweite, wird der Zugang erteilt.
- **Auto-Oeffnen:** Im Modus Automatik oeffnet die Tuer, sobald der Detektor der freien Seite jemanden erkennt, und bleibt `openTime` Sekunden nach der letzten Erkennung offen.
- **Gesperrt:** Die Tuer wird sofort geschlossen, auch wenn jemand im Tuerrahmen steht.
- **Dauerauf:** Die Tuer bleibt offen, bis der Modus gewechselt wird.

## Dateien

| Datei | Inhalt |
|---|---|
| `door.lua` | das Programm |
| `door_settings` | wird automatisch erzeugt (Einstellungen, Modus, Motorzustand) |
| `whitelist.txt` | wird automatisch erzeugt, ein Spielername pro Zeile |

## Fehlersuche

- **Tuer reagiert nicht:** Menuepunkt 8 (Diagnose) oeffnen und pruefen, ob der Detektor den Spieler sieht und ob die Zuweisung stimmt.
- **Signal invertiert:** Menuepunkt 6, Invertierung umschalten.
- **Motor wird nicht gefunden:** Der Peripheral-Typ muss `electric_motor` sein.
- **Relay wird nicht gefunden:** Unterstuetzt werden `redstone_relay` und `redstoneIntegrator`.
