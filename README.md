# PCMover - Programm Export/Import Tool

Ein Windows-Tool zum vollstaendigen 1:1 Klonen von Programmen zwischen PCs. Programme werden mit allen Dateien, Einstellungen, Verknuepfungen und Konfigurationen exportiert und auf dem Ziel-PC wiederhergestellt — ohne manuelle Nacharbeit.

## Konzept

PCMover erstellt eine vollstaendige Kopie eines installierten Programms, die auf einem anderen PC importiert werden kann. Dabei wird nicht nur der Programmordner kopiert, sondern alles was zum Betrieb noetig ist:

| Komponente | Beschreibung | Warum wichtig |
|---|---|---|
| Programmdateien | Installationsordner (`Program Files`) | Das Programm selbst |
| AppData | Roaming, Local, LocalLow | Benutzereinstellungen, Cache, Konfiguration |
| Registry (HKCU/HKLM) | Software-Keys, Uninstall-Eintraege | Programm ist im System "registriert" |
| Registry (HKCR) | Datei-Assoziationen, ProgIDs | Doppelklick auf Dateien oeffnet das richtige Programm |
| Start-Menü | Verknuepfungen im Startmenue | Programm ist im Startmenue auffindbar |
| Desktop | Desktop-Verknuepfungen | Schnellzugriff ueber Desktop-Icon |
| PATH-Eintraege | Umgebungsvariable PATH | CLI-Tools sind im Terminal erreichbar |
| Windows-Dienste | Hintergrunddienste des Programms | Dienste laufen nach Import automatisch |
| Geplante Tasks | Scheduled Tasks (Task Scheduler) | Automatische Hintergrundaufgaben funktionieren |
| Dokumente | Programmbezogene Ordner in `Dokumente` | Benutzerdaten und Projekte |

## Features

- **1:1 Programm-Klon**: Vollstaendiger Export aller Programmkomponenten
- **Automatischer Import**: Programme funktionieren nach Import sofort ohne manuelle Schritte
- **Windows Forms GUI**: Benutzerfreundliche grafische Oberflaeche mit klaren Anleitungen
- **Fortschrittsanzeige**: Visuelle Fortschrittsleisten fuer Export und Import
- **Multithreading**: Parallele Verarbeitung fuer schnellere Export/Import-Operationen (bis zu 4 gleichzeitige Jobs)
- **Intelligente Erkennung**: Verknuepfungen werden sowohl ueber Programmname als auch ueber Zielpfad erkannt
- **Datei-Assoziationen**: HKCR-Registry wird exportiert, damit Dateitypen korrekt zugeordnet bleiben
- **PATH-Migration**: Programmbezogene PATH-Eintraege werden auf dem Ziel-PC ergaenzt (ohne Duplikate)
- **Dienste-Management**: Windows-Dienste werden erkannt und nach Import automatisch gestartet
- **Task-Migration**: Geplante Tasks werden als XML exportiert und auf dem Ziel-PC registriert

## Verwendung

### Starten

Doppelklick auf `Start-PCMover.bat` oder in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File PCMover.ps1
```

### Programme exportieren

1. Oeffne den Tab "Programme exportieren"
2. Waehle die zu exportierenden Programme per Checkbox aus
3. Waehle den Export-Ordner (Standard: `Dokumente\PCMover_Exports`)
4. Klicke auf "Ausgewaehlte exportieren"

Der Export sammelt automatisch alle Komponenten:
- Programmdateien aus dem Installationsordner
- Einstellungen aus AppData (Roaming, Local, LocalLow)
- Registry-Eintraege (HKCU, HKLM und HKCR fuer Datei-Assoziationen)
- Start-Menü und Desktop-Verknuepfungen (Name- und Zielpfad-Matching)
- Programmbezogene PATH-Eintraege
- Zugehoerige Windows-Dienste (Name und Startmodus)
- Geplante Tasks als XML

### Programme importieren

**Schritt 1:** Waehle den Export-Ordner (enthaelt die exportierten Programme)
- Klicke auf "Durchsuchen" oder nutze den Standard-Pfad

**Schritt 2:** Waehle ein Programm aus der Liste
- Klicke auf eine Zeile in der Programmliste
- Details werden unten angezeigt (Komponenten, PATH-Eintraege, Dienste, Tasks)

**Schritt 3:** Klicke auf "Einstellungen importieren"

Der Import stellt automatisch wieder her:
1. Programmdateien und AppData (parallel via Multithreading)
2. Registry-Eintraege (HKCU, HKLM, HKCR)
3. Start-Menü und Desktop-Verknuepfungen
4. PATH-Eintraege (fehlende werden ergaenzt, vorhandene nicht dupliziert)
5. Windows-Dienste werden gestartet (wenn Startmodus "Automatisch")
6. Geplante Tasks werden im Task Scheduler registriert

## Export-Struktur

```
PCMover_Exports/
└── ProgrammName/
    ├── manifest.json          # Metadaten, Komponentenliste, PATH, Dienste, Tasks
    ├── export_log.txt         # Export-Protokoll
    ├── ProgramFiles/          # Programmdateien (Installationsordner)
    ├── AppData_Roaming/       # Roaming-Einstellungen
    ├── AppData_Local/         # Lokale Einstellungen
    ├── AppData_LocalLow/      # LocalLow-Einstellungen
    ├── Registry/              # Registry-Eintraege (.reg)
    │   ├── HKCU_*.reg         # Benutzer-Registry
    │   ├── HKLM_*.reg         # System-Registry
    │   └── HKCR_*.reg         # Datei-Assoziationen
    ├── Shortcuts/             # Verknuepfungen
    │   ├── StartMenu/         # Start-Menü (.lnk Dateien)
    │   └── Desktop/           # Desktop (.lnk Dateien)
    ├── ScheduledTasks/        # Geplante Tasks (.xml Dateien)
    └── Documents/             # Programmbezogene Dokumenten-Ordner
```

### manifest.json Felder

| Feld | Beschreibung |
|---|---|
| `ProgramName` | Name des Programms |
| `ExportDate` | Datum und Uhrzeit des Exports |
| `InstallLocation` | Urspruenglicher Installationspfad |
| `Components` | Liste aller exportierten Komponenten (Typ, Quell-/Zielpfad) |
| `PathEntries` | Programmbezogene PATH-Eintraege |
| `Services` | Zugehoerige Windows-Dienste (Name, Anzeigename, Startmodus) |
| `ScheduledTasks` | Geplante Tasks (Name, Pfad, XML-Datei) |

## Wie funktioniert die Erkennung?

### Programmdaten finden
PCMover sucht anhand des **ersten Worts** des Programmnamens nach zusammengehoerenden Daten:
- AppData-Ordner die den Programmnamen enthalten
- Dokumenten-Ordner die den Programmnamen enthalten
- Registry-Keys unter `HKCU\SOFTWARE`, `HKLM\SOFTWARE`, `HKLM\SOFTWARE\WOW6432Node`

### Verknuepfungen finden
Verknuepfungen werden ueber **zwei Methoden** erkannt:
1. **Name-Matching**: Der Dateiname der `.lnk`-Datei enthaelt den Programmnamen
2. **Zielpfad-Matching**: Das Ziel der Verknuepfung zeigt auf den Installationsordner

Dadurch werden auch Verknuepfungen gefunden die anders benannt sind als das Programm.

### Datei-Assoziationen finden
HKCR wird durchsucht nach:
- `HKCR\Applications\*ProgrammName*` — Programmregistrierungen
- `HKCR\Applications\<exe-name>.exe` — Fuer jede EXE im Installationsordner (max. 5)

### Windows-Dienste finden
Dienste werden ueber ihren **Ausfuehrungspfad** (`PathName`) erkannt:
- Pfad enthaelt den Programmnamen, oder
- Pfad enthaelt den Installationsordner

### Geplante Tasks finden
Tasks werden erkannt wenn:
- Der Task-Name oder Task-Pfad den Programmnamen enthaelt, oder
- Die auszufuehrende Aktion (`Execute`) auf den Installationsordner oder Programmnamen verweist

## Hinweise

- **Administratorrechte**: Dringend empfohlen fuer vollstaendigen Zugriff auf Registry (HKLM), Programmdateien, Windows-Dienste und geplante Tasks
- **Gleiche Windows-Version**: Export und Import sollten auf der gleichen Windows-Version erfolgen (z.B. Windows 11 → Windows 11)
- **Pfadunterschiede**: Wenn der Benutzername auf dem Ziel-PC anders ist, koennen Pfade in Registry-Eintraegen und Verknuepfungen abweichen
- **Antivirensoftware**: Kann den Import von Programmdateien oder Registry-Eintraegen blockieren — ggf. temporaer deaktivieren
- **Neustart**: Nach dem Import kann ein Neustart erforderlich sein, damit Windows-Dienste und PATH-Aenderungen vollstaendig wirksam werden

## Systemanforderungen

- Windows 10/11
- PowerShell 5.0 oder hoeher
- .NET Framework (fuer Windows Forms)
- Administratorrechte (empfohlen)

## Verwendete Microsoft Tools

| Tool | Verwendung |
|---|---|
| `robocopy` | Kopieren von Dateien und Ordnern (parallel) |
| `reg export` / `reg import` | Registry-Eintraege exportieren und importieren |
| `Get-ItemProperty` | Installierte Programme aus Registry auflisten |
| `WScript.Shell` COM | Verknuepfungen (.lnk) lesen und Zielpfad pruefen |
| `Get-ScheduledTask` / `Export-ScheduledTask` | Geplante Tasks erkennen und als XML exportieren |
| `schtasks /create` | Geplante Tasks aus XML importieren |
| `Get-WmiObject Win32_Service` | Windows-Dienste erkennen |
| `Start-Service` | Windows-Dienste nach Import starten |
| `[System.Environment]::SetEnvironmentVariable` | PATH-Eintraege setzen |
