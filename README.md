# PCMover - Programm Export/Import Tool

Ein Windows-Tool zum Exportieren und Importieren von Programmen inklusive ihrer Einstellungen und Daten.

## Features

- **Programm-Export**: Exportiert installierte Programme mit allen zugehoerigen Daten
- **Programm-Import**: Stellt exportierte Programme auf einem anderen PC wieder her
- **Windows Forms GUI**: Benutzerfreundliche grafische Oberflaeche mit klaren Anleitungen
- **Fortschrittsanzeige**: Visuelle Fortschrittsleisten fuer Export und Import
- **Multithreading**: Parallele Verarbeitung fuer schnellere Export/Import-Operationen (bis zu 4 gleichzeitige Jobs)
- **Verwendet Microsoft Command Line Tools**: `robocopy`, `reg export/import`

## Was wird exportiert?

- **Programmdateien**: Der Installationsordner des Programms
- **AppData**: Einstellungen aus Roaming, Local und LocalLow
- **Registry**: Programmspezifische Registry-Eintraege (HKCU, HKLM und HKCR)
- **Dokumente**: Programmbezogene Ordner im Dokumente-Verzeichnis
- **Verknuepfungen**: Start-Menü und Desktop-Verknuepfungen
- **Datei-Assoziationen**: HKCR-Registry fuer Dateityp-Zuordnungen
- **PATH-Eintraege**: Programmbezogene Eintraege in der PATH-Umgebungsvariable
- **Windows-Dienste**: Erkennung und automatischer Start nach Import
- **Geplante Tasks**: Scheduled Tasks des Programms

## Verwendung

### Starten

Doppelklick auf `Start-PCMover.bat` oder in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File PCMover.ps1
```

### Programme exportieren

1. Oeffne den Tab "Programme exportieren"
2. Waehle die zu exportierenden Programme per Checkbox aus
3. Waehle den Export-Ordner (Standard: Dokumente\PCMover_Exports)
4. Klicke auf "Ausgewaehlte exportieren"

### Programme importieren

**Schritt 1:** Waehle den Export-Ordner (enthaelt die exportierten Programme)
- Klicke auf "Durchsuchen" oder nutze den Standard-Pfad

**Schritt 2:** Waehle ein Programm aus der Liste
- Klicke auf eine Zeile in der Programmliste
- Details werden unten angezeigt

**Schritt 3:** Klicke auf "Einstellungen importieren"
- Stellt Einstellungen und Daten wieder her

## Export-Struktur

```
PCMover_Exports/
└── ProgrammName/
    ├── manifest.json          # Metadaten und Komponentenliste
    ├── export_log.txt         # Export-Protokoll
    ├── ProgramFiles/          # Programmdateien
    ├── AppData_Roaming/       # Roaming-Einstellungen
    ├── AppData_Local/         # Lokale Einstellungen
    ├── Registry/              # Registry-Eintraege (.reg) inkl. HKCR
    ├── Shortcuts/             # Start-Menü und Desktop-Verknuepfungen
    │   ├── StartMenu/
    │   └── Desktop/
    ├── ScheduledTasks/        # Geplante Tasks (XML)
    └── Documents/             # Dokumenten-Ordner
```

## Hinweise

- **Administratorrechte**: Fuer vollstaendigen Zugriff auf Registry und Programmdateien empfohlen

## Systemanforderungen

- Windows 10/11
- PowerShell 5.0 oder hoeher
- .NET Framework (fuer Windows Forms)

## Verwendete Microsoft Tools

- `robocopy` - Zum Kopieren von Dateien und Ordnern
- `reg export/import` - Zum Exportieren/Importieren von Registry-Eintraegen
- `Get-ItemProperty` - Zum Auflisten installierter Programme
- `schtasks` - Zum Exportieren/Importieren von geplanten Tasks
- `Get-ScheduledTask` / `Export-ScheduledTask` - Task-Erkennung und XML-Export
- `Get-WmiObject Win32_Service` - Windows-Dienste erkennen
