# PCMover - Programm Export/Import Tool
# Verwendet Windows Forms fuer die UI und Microsoft Command Line Tools
# Mit Fortschrittsanzeige und Multithreading
# UTF-8 Encoding fuer deutsche Umlaute

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Globale Variablen
$script:ExportPath = "$env:USERPROFILE\Documents\PCMover_Exports"
$script:MaxParallelJobs = 4

# Funktion: Installierte Programme auflisten
function Get-InstalledPrograms {
    $programs = @()
    
    # 64-bit Programme
    $regPath64 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    # 32-bit Programme auf 64-bit System
    $regPath32 = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    # Benutzer-installierte Programme
    $regPathUser = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    
    $allPaths = @($regPath64, $regPath32, $regPathUser)
    
    foreach ($path in $allPaths) {
        try {
            $items = Get-ItemProperty $path -ErrorAction SilentlyContinue | 
                Where-Object { $_.DisplayName -and $_.DisplayName -ne "" } |
                Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation, UninstallString, InstallDate
            $programs += $items
        } catch { }
    }
    
    return $programs | Sort-Object DisplayName -Unique
}

# Funktion: Einzelne Komponente exportieren (fuer Multithreading)
function Export-Component {
    param(
        [string]$Type,
        [string]$SourcePath,
        [string]$DestPath,
        [string]$LogFile
    )
    
    $result = @{
        Success = $false
        Type = $Type
        Source = $SourcePath
        Destination = $DestPath
        Error = ""
    }
    
    try {
        if (Test-Path $SourcePath) {
            New-Item -ItemType Directory -Path $DestPath -Force | Out-Null
            robocopy $SourcePath $DestPath /E /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
            $result.Success = $true
        }
    } catch {
        $result.Error = $_.Exception.Message
    }
    
    return $result
}

# Funktion: Programm exportieren mit Fortschritt
function Export-Program {
    param(
        [string]$ProgramName,
        [string]$InstallLocation,
        [string]$ExportFolder,
        [System.Windows.Forms.ProgressBar]$ProgressBar,
        [System.Windows.Forms.Label]$StatusLabel,
        [System.Windows.Forms.Form]$Form
    )
    
    $exportDir = Join-Path $ExportFolder ($ProgramName -replace '[\\/:*?"<>|]', '_')
    New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
    
    $logFile = Join-Path $exportDir "export_log.txt"
    $manifestFile = Join-Path $exportDir "manifest.json"
    
    $manifest = @{
        ProgramName = $ProgramName
        ExportDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        InstallLocation = $InstallLocation
        Components = @()
        PathEntries = @()
        Services = @()
        ScheduledTasks = @()
    }
    
    Add-Content $logFile "=== PCMover Export Log ===" -Encoding UTF8
    Add-Content $logFile "Programm: $ProgramName" -Encoding UTF8
    Add-Content $logFile "Datum: $(Get-Date)" -Encoding UTF8
    Add-Content $logFile "" -Encoding UTF8
    
    # Sammle alle zu exportierenden Komponenten
    $exportTasks = @()
    $searchPattern = $ProgramName.Split()[0]
    
    # 1. Programmdateien
    if ($InstallLocation -and (Test-Path $InstallLocation)) {
        $exportTasks += @{
            Type = "ProgramFiles"
            Source = $InstallLocation
            Dest = Join-Path $exportDir "ProgramFiles"
        }
    }
    
    # 2. AppData Ordner
    $appDataPaths = @(
        @{Name="AppData_Roaming"; Path="$env:APPDATA"},
        @{Name="AppData_Local"; Path="$env:LOCALAPPDATA"},
        @{Name="AppData_LocalLow"; Path="$env:USERPROFILE\AppData\LocalLow"}
    )
    
    foreach ($appData in $appDataPaths) {
        $matchingFolders = Get-ChildItem -Path $appData.Path -Directory -ErrorAction SilentlyContinue | 
            Where-Object { $_.Name -like "*$searchPattern*" }
        
        foreach ($folder in $matchingFolders) {
            $exportTasks += @{
                Type = $appData.Name
                Source = $folder.FullName
                Dest = Join-Path $exportDir "$($appData.Name)\$($folder.Name)"
            }
        }
    }
    
    # 3. Dokumente
    $documentsPath = [Environment]::GetFolderPath('MyDocuments')
    $matchingDocFolders = Get-ChildItem -Path $documentsPath -Directory -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -like "*$searchPattern*" }
    
    foreach ($folder in $matchingDocFolders) {
        $exportTasks += @{
            Type = "Documents"
            Source = $folder.FullName
            Dest = Join-Path $exportDir "Documents\$($folder.Name)"
        }
    }
    
    # 4. Start-Menü Verknuepfungen
    $shortcutExportDir = Join-Path $exportDir "Shortcuts"
    New-Item -ItemType Directory -Path (Join-Path $shortcutExportDir "StartMenu") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $shortcutExportDir "Desktop") -Force | Out-Null

    $shell = New-Object -ComObject WScript.Shell
    $startMenuPaths = @(
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs"
    )
    foreach ($smPath in $startMenuPaths) {
        Get-ChildItem -Path $smPath -Recurse -Filter "*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $lnk = $shell.CreateShortcut($_.FullName)
                $matchByName = $_.BaseName -like "*$searchPattern*"
                $matchByTarget = $InstallLocation -and $lnk.TargetPath -like "*$InstallLocation*"
                if ($matchByName -or $matchByTarget) {
                    $destFile = Join-Path $shortcutExportDir "StartMenu\$($_.Name)"
                    Copy-Item $_.FullName $destFile -Force -ErrorAction SilentlyContinue
                    if (Test-Path $destFile) {
                        $manifest.Components += @{Type="StartMenu"; Source=$_.FullName; File=$destFile}
                        Add-Content $logFile "Verknuepfung exportiert: $($_.FullName)" -Encoding UTF8
                    }
                }
            } catch {}
        }
    }

    # 5. Desktop-Verknuepfungen
    $desktopPaths = @("$env:USERPROFILE\Desktop", "C:\Users\Public\Desktop")
    foreach ($dPath in $desktopPaths) {
        Get-ChildItem -Path $dPath -Filter "*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $lnk = $shell.CreateShortcut($_.FullName)
                $matchByName = $_.BaseName -like "*$searchPattern*"
                $matchByTarget = $InstallLocation -and $lnk.TargetPath -like "*$InstallLocation*"
                if ($matchByName -or $matchByTarget) {
                    $destFile = Join-Path $shortcutExportDir "Desktop\$($_.Name)"
                    Copy-Item $_.FullName $destFile -Force -ErrorAction SilentlyContinue
                    if (Test-Path $destFile) {
                        $manifest.Components += @{Type="Desktop"; Source=$_.FullName; File=$destFile}
                        Add-Content $logFile "Desktop-Verknuepfung exportiert: $($_.FullName)" -Encoding UTF8
                    }
                }
            } catch {}
        }
    }
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null

    $totalTasks = $exportTasks.Count + 3  # +1 Verknuepfungen, +1 Registry, +1 Tasks/Dienste/PATH
    $completedTasks = 0
    
    if ($ProgressBar) {
        $ProgressBar.Maximum = 100
        $ProgressBar.Value = 0
    }
    
    # Parallele Ausfuehrung mit Runspaces
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $script:MaxParallelJobs)
    $runspacePool.Open()
    
    $jobs = @()
    
    $scriptBlock = {
        param($Source, $Dest, $Type)
        
        $result = @{
            Success = $false
            Type = $Type
            Source = $Source
            Destination = $Dest
            Error = ""
        }
        
        try {
            if (Test-Path $Source) {
                New-Item -ItemType Directory -Path $Dest -Force | Out-Null
                $robocopyResult = & robocopy $Source $Dest /E /R:1 /W:1 /NFL /NDL /NJH /NJS 2>&1
                $result.Success = $true
            }
        } catch {
            $result.Error = $_.Exception.Message
        }
        
        return $result
    }
    
    # Starte alle Kopier-Jobs parallel
    foreach ($task in $exportTasks) {
        $powershell = [powershell]::Create().AddScript($scriptBlock)
        $powershell.AddArgument($task.Source)
        $powershell.AddArgument($task.Dest)
        $powershell.AddArgument($task.Type)
        $powershell.RunspacePool = $runspacePool
        
        $jobs += @{
            PowerShell = $powershell
            Handle = $powershell.BeginInvoke()
            Task = $task
        }
    }
    
    # Warte auf Abschluss und aktualisiere Fortschritt
    while ($jobs.Count -gt 0) {
        $completedJobs = @()
        
        foreach ($job in $jobs) {
            if ($job.Handle.IsCompleted) {
                $result = $job.PowerShell.EndInvoke($job.Handle)
                $job.PowerShell.Dispose()
                
                $completedTasks++
                
                if ($result -and $result.Success) {
                    $manifest.Components += @{
                        Type = $result.Type
                        Source = $result.Source
                        Destination = $result.Destination
                    }
                    Add-Content $logFile "Kopiert: $($result.Source) -> Erfolgreich" -Encoding UTF8
                } else {
                    Add-Content $logFile "Fehler bei: $($job.Task.Source)" -Encoding UTF8
                }
                
                $completedJobs += $job
                
                # Update UI
                if ($ProgressBar -and $Form) {
                    $percent = [int](($completedTasks / $totalTasks) * 100)
                    $ProgressBar.Value = [Math]::Min($percent, 100)
                    if ($StatusLabel) {
                        $StatusLabel.Text = "Exportiere $ProgramName... ($completedTasks/$totalTasks Komponenten)"
                    }
                    $Form.Refresh()
                }
            }
        }
        
        foreach ($completedJob in $completedJobs) {
            $jobs = $jobs | Where-Object { $_ -ne $completedJob }
        }
        
        if ($jobs.Count -gt 0) {
            Start-Sleep -Milliseconds 100
        }
    }
    
    $runspacePool.Close()
    $runspacePool.Dispose()
    
    # 4. Registry exportieren (sequentiell, da reg.exe nicht parallel sicher ist)
    if ($StatusLabel) {
        $StatusLabel.Text = "Exportiere $ProgramName... Registry-Eintraege"
    }
    if ($Form) { $Form.Refresh() }
    
    $regExportDir = Join-Path $exportDir "Registry"
    New-Item -ItemType Directory -Path $regExportDir -Force | Out-Null
    
    # HKCR PSDrive erstellen fuer Datei-Assoziationen
    if (-not (Get-PSDrive -Name HKCR -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -ErrorAction SilentlyContinue | Out-Null
    }

    # Suche Registry-Keys direkt ohne tiefe Rekursion (verhindert Crashes)
    $regSearchPaths = @(
        "HKCU:\SOFTWARE\$searchPattern",
        "HKCU:\SOFTWARE\*$searchPattern*",
        "HKLM:\SOFTWARE\$searchPattern",
        "HKLM:\SOFTWARE\*$searchPattern*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*$searchPattern*",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*$searchPattern*",
        "HKLM:\SOFTWARE\WOW6432Node\*$searchPattern*",
        "HKCR:\Applications\*$searchPattern*"
    )

    # HKCR: Datei-Assoziationen ueber Programm-Executables finden
    if ($InstallLocation -and (Test-Path $InstallLocation)) {
        $exeFiles = Get-ChildItem -Path $InstallLocation -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 5
        foreach ($exe in $exeFiles) {
            $regSearchPaths += "HKCR:\Applications\$($exe.Name)"
        }
    }
    
    $exportedKeys = @{}  # Verhindert doppelte Exports
    
    foreach ($searchPath in $regSearchPaths) {
        $hive = if ($searchPath -like "HKCU:*") { "HKCU" } elseif ($searchPath -like "HKCR:*") { "HKCR" } else { "HKLM" }
        
        try {
            $matchingKeys = @()
            try {
                $matchingKeys = Get-Item -Path $searchPath -ErrorAction SilentlyContinue 2>$null
            } catch { }
            
            if (-not $matchingKeys) { continue }
            
            foreach ($key in $matchingKeys) {
                if (-not $key -or -not $key.PSPath) { continue }
                
                try {
                    $keyName = $key.PSPath -replace ".*::", ""
                    if (-not $keyName) { continue }
                    
                    # Verhindere doppelte Exports
                    if ($exportedKeys.ContainsKey($keyName)) { continue }
                    $exportedKeys[$keyName] = $true
                    
                    $safeKeyName = ($keyName -replace '[\\/:*?"<>|]', '_')
                    if ($safeKeyName.Length -gt 100) {
                        $safeKeyName = $safeKeyName.Substring(0, 100)
                    }
                    $safeKeyName += ".reg"
                    $regFile = Join-Path $regExportDir "$hive`_$safeKeyName"
                    
                    $fullKeyPath = $key.PSPath -replace "Microsoft.PowerShell.Core\\Registry::", ""
                    if (-not $fullKeyPath) { continue }
                    
                    # reg export mit robuster Fehlerbehandlung
                    $regResult = $null
                    try {
                        $regResult = & reg export "$fullKeyPath" "$regFile" /y 2>&1
                        if (Test-Path $regFile) {
                            $manifest.Components += @{Type="Registry"; Key=$fullKeyPath; File=$regFile}
                            try { Add-Content $logFile "Registry exportiert: $fullKeyPath" -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
                        }
                    } catch {
                        try { Add-Content $logFile "Registry Fehler: $fullKeyPath - $_" -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
                    }
                } catch {
                    # Einzelnen Key-Fehler ignorieren, weitermachen
                    continue
                }
            }
        } catch {
            # Pfad-Fehler ignorieren, weitermachen
            continue
        }
    }
    
    $completedTasks++
    if ($ProgressBar -and $Form) {
        $percent = [int](($completedTasks / $totalTasks) * 100)
        $ProgressBar.Value = [Math]::Min($percent, 100)
        if ($StatusLabel) { $StatusLabel.Text = "Exportiere $ProgramName... PATH/Dienste/Tasks" }
        $Form.Refresh()
    }

    # 7. PATH-Eintraege sichern
    $pathEntriesToMigrate = @()
    $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    foreach ($pathStr in @($userPath, $machinePath)) {
        if ($pathStr) {
            $pathStr -split ';' | Where-Object {
                $_ -and ($_ -like "*$searchPattern*" -or ($InstallLocation -and $_ -like "*$InstallLocation*"))
            } | ForEach-Object {
                if ($_ -notin $pathEntriesToMigrate) {
                    $pathEntriesToMigrate += $_
                }
            }
        }
    }
    $manifest.PathEntries = $pathEntriesToMigrate
    if ($pathEntriesToMigrate.Count -gt 0) {
        Add-Content $logFile "PATH-Eintraege: $($pathEntriesToMigrate -join '; ')" -Encoding UTF8
    }

    # 8. Windows-Dienste erkennen
    $relatedServices = @()
    try {
        Get-WmiObject Win32_Service -ErrorAction SilentlyContinue | Where-Object {
            $_.PathName -and ($_.PathName -like "*$searchPattern*" -or ($InstallLocation -and $_.PathName -like "*$InstallLocation*"))
        } | ForEach-Object {
            $relatedServices += @{Name=$_.Name; DisplayName=$_.DisplayName; StartMode=$_.StartMode}
            Add-Content $logFile "Dienst erkannt: $($_.Name) ($($_.StartMode))" -Encoding UTF8
        }
    } catch {}
    $manifest.Services = $relatedServices

    # 9. Geplante Tasks exportieren
    $taskExportDir = Join-Path $exportDir "ScheduledTasks"
    New-Item -ItemType Directory -Path $taskExportDir -Force | Out-Null
    $scheduledTasks = @()
    try {
        Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
            $matchTask = $false
            if ($_.TaskName -like "*$searchPattern*" -or $_.TaskPath -like "*$searchPattern*") { $matchTask = $true }
            if (-not $matchTask -and $InstallLocation) {
                foreach ($action in $_.Actions) {
                    if ($action.Execute -like "*$InstallLocation*" -or $action.Execute -like "*$searchPattern*") {
                        $matchTask = $true
                        break
                    }
                }
            }
            $matchTask
        } | ForEach-Object {
            $safeName = ($_.TaskName -replace '[\\/:*?"<>|]', '_')
            $xmlFile = Join-Path $taskExportDir "$safeName.xml"
            try {
                Export-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath | Out-File $xmlFile -Encoding UTF8
                $scheduledTasks += @{Name=$_.TaskName; TaskPath=$_.TaskPath; XmlFile=$xmlFile}
                Add-Content $logFile "Task exportiert: $($_.TaskName)" -Encoding UTF8
            } catch {}
        }
    } catch {}
    $manifest.ScheduledTasks = $scheduledTasks

    $completedTasks++
    if ($ProgressBar) {
        $ProgressBar.Value = 100
    }

    # Manifest speichern
    $manifest | ConvertTo-Json -Depth 10 | Out-File $manifestFile -Encoding UTF8
    
    Add-Content $logFile "" -Encoding UTF8
    Add-Content $logFile "=== Export abgeschlossen ===" -Encoding UTF8
    
    return $exportDir
}

# Funktion: Programm importieren mit Fortschritt
function Import-Program {
    param(
        [string]$ImportFolder,
        [System.Windows.Forms.ProgressBar]$ProgressBar,
        [System.Windows.Forms.Label]$StatusLabel,
        [System.Windows.Forms.Form]$Form
    )
    
    $manifestFile = Join-Path $ImportFolder "manifest.json"
    
    if (-not (Test-Path $manifestFile)) {
        return "Fehler: Keine manifest.json gefunden in $ImportFolder"
    }
    
    $manifest = Get-Content $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $logFile = Join-Path $ImportFolder "import_log.txt"
    
    Add-Content $logFile "" -Encoding UTF8
    Add-Content $logFile "=== PCMover Import Log ===" -Encoding UTF8
    Add-Content $logFile "Programm: $($manifest.ProgramName)" -Encoding UTF8
    Add-Content $logFile "Import-Datum: $(Get-Date)" -Encoding UTF8
    Add-Content $logFile "" -Encoding UTF8
    
    $totalComponents = $manifest.Components.Count
    $currentComponent = 0
    
    if ($ProgressBar) {
        $ProgressBar.Maximum = 100
        $ProgressBar.Value = 0
    }
    
    # Trenne Datei-Komponenten, Registry, und Verknuepfungen
    $fileComponents = $manifest.Components | Where-Object { $_.Type -notin @("Registry", "StartMenu", "Desktop") }
    $registryComponents = $manifest.Components | Where-Object { $_.Type -eq "Registry" }
    $shortcutComponents = $manifest.Components | Where-Object { $_.Type -in @("StartMenu", "Desktop") }
    
    # Parallele Verarbeitung fuer Datei-Komponenten
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $script:MaxParallelJobs)
    $runspacePool.Open()
    
    $jobs = @()
    
    $importScriptBlock = {
        param($Source, $Dest, $Type)
        
        $result = @{
            Success = $false
            Type = $Type
            Source = $Source
            Destination = $Dest
            Error = ""
        }
        
        try {
            if (Test-Path $Source) {
                New-Item -ItemType Directory -Path $Dest -Force | Out-Null
                $robocopyResult = & robocopy $Source $Dest /E /R:1 /W:1 /NFL /NDL /NJH /NJS 2>&1
                $result.Success = $true
            }
        } catch {
            $result.Error = $_.Exception.Message
        }
        
        return $result
    }
    
    # Starte Import-Jobs parallel
    foreach ($component in $fileComponents) {
        $sourcePath = $component.Destination  # Im Export ist Destination der Speicherort
        $destPath = $component.Source         # Source ist der Original-Pfad
        
        if (Test-Path $sourcePath) {
            $powershell = [powershell]::Create().AddScript($importScriptBlock)
            $powershell.AddArgument($sourcePath)
            $powershell.AddArgument($destPath)
            $powershell.AddArgument($component.Type)
            $powershell.RunspacePool = $runspacePool
            
            $jobs += @{
                PowerShell = $powershell
                Handle = $powershell.BeginInvoke()
                Component = $component
            }
        }
    }
    
    # Warte auf Abschluss
    while ($jobs.Count -gt 0) {
        $completedJobs = @()
        
        foreach ($job in $jobs) {
            if ($job.Handle.IsCompleted) {
                $result = $job.PowerShell.EndInvoke($job.Handle)
                $job.PowerShell.Dispose()
                
                $currentComponent++
                
                if ($result -and $result.Success) {
                    Add-Content $logFile "Wiederhergestellt: $($result.Type) -> $($result.Destination)" -Encoding UTF8
                } else {
                    Add-Content $logFile "Fehler bei: $($job.Component.Type)" -Encoding UTF8
                }
                
                $completedJobs += $job
                
                # Update UI
                if ($ProgressBar -and $Form) {
                    $percent = [int](($currentComponent / $totalComponents) * 100)
                    $ProgressBar.Value = [Math]::Min($percent, 100)
                    if ($StatusLabel) {
                        $StatusLabel.Text = "Importiere... ($currentComponent/$totalComponents Komponenten)"
                    }
                    $Form.Refresh()
                }
            }
        }
        
        foreach ($completedJob in $completedJobs) {
            $jobs = $jobs | Where-Object { $_ -ne $completedJob }
        }
        
        if ($jobs.Count -gt 0) {
            Start-Sleep -Milliseconds 100
        }
    }
    
    $runspacePool.Close()
    $runspacePool.Dispose()
    
    # Registry-Import (sequentiell)
    foreach ($component in $registryComponents) {
        $currentComponent++
        
        if (Test-Path $component.File) {
            if ($StatusLabel) {
                $StatusLabel.Text = "Importiere Registry... ($currentComponent/$totalComponents)"
            }
            if ($Form) { $Form.Refresh() }
            
            try {
                reg import $component.File 2>&1 | Out-Null
                Add-Content $logFile "Registry importiert: $($component.Key)" -Encoding UTF8
            } catch {
                Add-Content $logFile "Registry Fehler: $($component.Key) - $_" -Encoding UTF8
            }
        }
        
        if ($ProgressBar) {
            $percent = [int](($currentComponent / $totalComponents) * 100)
            $ProgressBar.Value = [Math]::Min($percent, 100)
        }
    }
    
    # Verknuepfungen importieren
    foreach ($component in $shortcutComponents) {
        $currentComponent++
        if (Test-Path $component.File) {
            try {
                $destPath = $component.Source
                $destDir = Split-Path $destPath -Parent
                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                Copy-Item $component.File $destPath -Force -ErrorAction SilentlyContinue
                Add-Content $logFile "Verknuepfung wiederhergestellt: $destPath" -Encoding UTF8
            } catch {
                Add-Content $logFile "Verknuepfung Fehler: $destPath - $_" -Encoding UTF8
            }
        }
        if ($ProgressBar -and $totalComponents -gt 0) {
            $percent = [int](($currentComponent / $totalComponents) * 100)
            $ProgressBar.Value = [Math]::Min($percent, 100)
        }
    }

    # PATH-Eintraege wiederherstellen
    if ($manifest.PathEntries -and $manifest.PathEntries.Count -gt 0) {
        if ($StatusLabel) { $StatusLabel.Text = "Importiere PATH-Eintraege..." }
        if ($Form) { $Form.Refresh() }

        $currentUserPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
        $newEntries = @()
        foreach ($entry in $manifest.PathEntries) {
            if ($currentUserPath -notlike "*$entry*") {
                $newEntries += $entry
            }
        }
        if ($newEntries.Count -gt 0) {
            $updated = ($currentUserPath.TrimEnd(';') + ';' + ($newEntries -join ';')).TrimStart(';')
            [System.Environment]::SetEnvironmentVariable('Path', $updated, 'User')
            Add-Content $logFile "PATH aktualisiert: $($newEntries -join '; ')" -Encoding UTF8
        }
    }

    # Windows-Dienste starten
    if ($manifest.Services -and $manifest.Services.Count -gt 0) {
        if ($StatusLabel) { $StatusLabel.Text = "Starte Windows-Dienste..." }
        if ($Form) { $Form.Refresh() }

        foreach ($svc in $manifest.Services) {
            try {
                $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
                if ($service -and $service.Status -ne 'Running' -and $svc.StartMode -eq 'Auto') {
                    Start-Service -Name $svc.Name -ErrorAction SilentlyContinue
                    Add-Content $logFile "Dienst gestartet: $($svc.Name)" -Encoding UTF8
                }
            } catch {
                Add-Content $logFile "Dienst Fehler: $($svc.Name) - $_" -Encoding UTF8
            }
        }
    }

    # Geplante Tasks importieren
    if ($manifest.ScheduledTasks -and $manifest.ScheduledTasks.Count -gt 0) {
        if ($StatusLabel) { $StatusLabel.Text = "Importiere geplante Tasks..." }
        if ($Form) { $Form.Refresh() }

        foreach ($task in $manifest.ScheduledTasks) {
            if (Test-Path $task.XmlFile) {
                try {
                    & schtasks /create /xml "$($task.XmlFile)" /tn "$($task.Name)" /f 2>&1 | Out-Null
                    Add-Content $logFile "Task registriert: $($task.Name)" -Encoding UTF8
                } catch {
                    Add-Content $logFile "Task Fehler: $($task.Name) - $_" -Encoding UTF8
                }
            }
        }
    }

    if ($ProgressBar) {
        $ProgressBar.Value = 100
    }

    Add-Content $logFile "" -Encoding UTF8
    Add-Content $logFile "=== Import abgeschlossen ===" -Encoding UTF8

    return "Import erfolgreich abgeschlossen. Siehe Log: $logFile"
}

# ============================================
# Windows Forms GUI
# ============================================

$form = New-Object System.Windows.Forms.Form
$form.Text = "PCMover - Programm Export/Import Tool"
$form.Size = New-Object System.Drawing.Size(800, 700)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# TabControl fuer Export/Import
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(10, 10)
$tabControl.Size = New-Object System.Drawing.Size(765, 640)

# ============================================
# Tab: Export
# ============================================
$tabExport = New-Object System.Windows.Forms.TabPage
$tabExport.Text = "Programme exportieren"
$tabExport.Padding = New-Object System.Windows.Forms.Padding(10)

# Label
$lblPrograms = New-Object System.Windows.Forms.Label
$lblPrograms.Location = New-Object System.Drawing.Point(10, 10)
$lblPrograms.Size = New-Object System.Drawing.Size(200, 20)
$lblPrograms.Text = "Installierte Programme:"
$tabExport.Controls.Add($lblPrograms)

# Suche
$lblSearch = New-Object System.Windows.Forms.Label
$lblSearch.Location = New-Object System.Drawing.Point(400, 10)
$lblSearch.Size = New-Object System.Drawing.Size(60, 20)
$lblSearch.Text = "Suche:"
$tabExport.Controls.Add($lblSearch)

$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(460, 7)
$txtSearch.Size = New-Object System.Drawing.Size(280, 25)
$tabExport.Controls.Add($txtSearch)

# ListView fuer Programme
$listPrograms = New-Object System.Windows.Forms.ListView
$listPrograms.Location = New-Object System.Drawing.Point(10, 35)
$listPrograms.Size = New-Object System.Drawing.Size(730, 250)
$listPrograms.View = [System.Windows.Forms.View]::Details
$listPrograms.FullRowSelect = $true
$listPrograms.GridLines = $true
$listPrograms.CheckBoxes = $true

$listPrograms.Columns.Add("Programm", 250) | Out-Null
$listPrograms.Columns.Add("Version", 100) | Out-Null
$listPrograms.Columns.Add("Herausgeber", 180) | Out-Null
$listPrograms.Columns.Add("Installationspfad", 200) | Out-Null

$tabExport.Controls.Add($listPrograms)

# Export-Pfad
$lblExportPath = New-Object System.Windows.Forms.Label
$lblExportPath.Location = New-Object System.Drawing.Point(10, 295)
$lblExportPath.Size = New-Object System.Drawing.Size(100, 20)
$lblExportPath.Text = "Export-Ordner:"
$tabExport.Controls.Add($lblExportPath)

$txtExportPath = New-Object System.Windows.Forms.TextBox
$txtExportPath.Location = New-Object System.Drawing.Point(110, 292)
$txtExportPath.Size = New-Object System.Drawing.Size(530, 25)
$txtExportPath.Text = $script:ExportPath
$tabExport.Controls.Add($txtExportPath)

$btnBrowseExport = New-Object System.Windows.Forms.Button
$btnBrowseExport.Location = New-Object System.Drawing.Point(650, 290)
$btnBrowseExport.Size = New-Object System.Drawing.Size(90, 27)
$btnBrowseExport.Text = "Durchsuchen"
$tabExport.Controls.Add($btnBrowseExport)

# Optionen
$grpOptions = New-Object System.Windows.Forms.GroupBox
$grpOptions.Location = New-Object System.Drawing.Point(10, 325)
$grpOptions.Size = New-Object System.Drawing.Size(730, 60)
$grpOptions.Text = "Export-Optionen"

$chkProgramFiles = New-Object System.Windows.Forms.CheckBox
$chkProgramFiles.Location = New-Object System.Drawing.Point(15, 25)
$chkProgramFiles.Size = New-Object System.Drawing.Size(130, 25)
$chkProgramFiles.Text = "Programmdateien"
$chkProgramFiles.Checked = $true
$grpOptions.Controls.Add($chkProgramFiles)

$chkAppData = New-Object System.Windows.Forms.CheckBox
$chkAppData.Location = New-Object System.Drawing.Point(155, 25)
$chkAppData.Size = New-Object System.Drawing.Size(100, 25)
$chkAppData.Text = "AppData"
$chkAppData.Checked = $true
$grpOptions.Controls.Add($chkAppData)

$chkRegistry = New-Object System.Windows.Forms.CheckBox
$chkRegistry.Location = New-Object System.Drawing.Point(265, 25)
$chkRegistry.Size = New-Object System.Drawing.Size(100, 25)
$chkRegistry.Text = "Registry"
$chkRegistry.Checked = $true
$grpOptions.Controls.Add($chkRegistry)

$chkDocuments = New-Object System.Windows.Forms.CheckBox
$chkDocuments.Location = New-Object System.Drawing.Point(375, 25)
$chkDocuments.Size = New-Object System.Drawing.Size(120, 25)
$chkDocuments.Text = "Dokumente"
$chkDocuments.Checked = $true
$grpOptions.Controls.Add($chkDocuments)

$chkShortcuts = New-Object System.Windows.Forms.CheckBox
$chkShortcuts.Location = New-Object System.Drawing.Point(505, 25)
$chkShortcuts.Size = New-Object System.Drawing.Size(130, 25)
$chkShortcuts.Text = "Verknuepfungen"
$chkShortcuts.Checked = $true
$grpOptions.Controls.Add($chkShortcuts)

$tabExport.Controls.Add($grpOptions)

# Fortschrittsleiste Export
$lblProgressExport = New-Object System.Windows.Forms.Label
$lblProgressExport.Location = New-Object System.Drawing.Point(10, 395)
$lblProgressExport.Size = New-Object System.Drawing.Size(100, 20)
$lblProgressExport.Text = "Fortschritt:"
$tabExport.Controls.Add($lblProgressExport)

$progressExport = New-Object System.Windows.Forms.ProgressBar
$progressExport.Location = New-Object System.Drawing.Point(110, 393)
$progressExport.Size = New-Object System.Drawing.Size(630, 25)
$progressExport.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
$progressExport.Minimum = 0
$progressExport.Maximum = 100
$progressExport.Value = 0
$tabExport.Controls.Add($progressExport)

# Buttons
$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Location = New-Object System.Drawing.Point(10, 430)
$btnRefresh.Size = New-Object System.Drawing.Size(120, 35)
$btnRefresh.Text = "Aktualisieren"
$tabExport.Controls.Add($btnRefresh)

$btnSelectAll = New-Object System.Windows.Forms.Button
$btnSelectAll.Location = New-Object System.Drawing.Point(140, 430)
$btnSelectAll.Size = New-Object System.Drawing.Size(120, 35)
$btnSelectAll.Text = "Alle auswaehlen"
$tabExport.Controls.Add($btnSelectAll)

$btnDeselectAll = New-Object System.Windows.Forms.Button
$btnDeselectAll.Location = New-Object System.Drawing.Point(270, 430)
$btnDeselectAll.Size = New-Object System.Drawing.Size(120, 35)
$btnDeselectAll.Text = "Keine auswaehlen"
$tabExport.Controls.Add($btnDeselectAll)

$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Location = New-Object System.Drawing.Point(560, 430)
$btnExport.Size = New-Object System.Drawing.Size(180, 35)
$btnExport.Text = "Ausgewaehlte exportieren"
$btnExport.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnExport.ForeColor = [System.Drawing.Color]::White
$tabExport.Controls.Add($btnExport)

# Statusleiste Export
$lblStatusExport = New-Object System.Windows.Forms.Label
$lblStatusExport.Location = New-Object System.Drawing.Point(10, 475)
$lblStatusExport.Size = New-Object System.Drawing.Size(730, 40)
$lblStatusExport.Text = "Bereit. Waehlen Sie Programme aus und klicken Sie auf 'Ausgewaehlte exportieren'."
$tabExport.Controls.Add($lblStatusExport)

# Gesamtfortschritt Export
$lblTotalProgressExport = New-Object System.Windows.Forms.Label
$lblTotalProgressExport.Location = New-Object System.Drawing.Point(10, 520)
$lblTotalProgressExport.Size = New-Object System.Drawing.Size(100, 20)
$lblTotalProgressExport.Text = "Gesamt:"
$tabExport.Controls.Add($lblTotalProgressExport)

$progressTotalExport = New-Object System.Windows.Forms.ProgressBar
$progressTotalExport.Location = New-Object System.Drawing.Point(110, 518)
$progressTotalExport.Size = New-Object System.Drawing.Size(630, 25)
$progressTotalExport.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
$progressTotalExport.Minimum = 0
$progressTotalExport.Maximum = 100
$progressTotalExport.Value = 0
$tabExport.Controls.Add($progressTotalExport)

# ============================================
# Tab: Import
# ============================================
$tabImport = New-Object System.Windows.Forms.TabPage
$tabImport.Text = "Programme importieren"
$tabImport.Padding = New-Object System.Windows.Forms.Padding(10)

# Anleitung Panel
$pnlAnleitung = New-Object System.Windows.Forms.Panel
$pnlAnleitung.Location = New-Object System.Drawing.Point(10, 10)
$pnlAnleitung.Size = New-Object System.Drawing.Size(730, 60)
$pnlAnleitung.BackColor = [System.Drawing.Color]::FromArgb(230, 240, 255)
$pnlAnleitung.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

$lblAnleitung = New-Object System.Windows.Forms.Label
$lblAnleitung.Location = New-Object System.Drawing.Point(10, 5)
$lblAnleitung.Size = New-Object System.Drawing.Size(710, 50)
$lblAnleitung.Text = "ANLEITUNG: 1) Waehlen Sie den Export-Ordner (Standard: Dokumente\PCMover_Exports)`n2) Klicken Sie auf ein Programm in der Liste unten`n3) Klicken Sie auf 'Einstellungen importieren'"
$lblAnleitung.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$pnlAnleitung.Controls.Add($lblAnleitung)
$tabImport.Controls.Add($pnlAnleitung)

# Import-Pfad
$lblImportPath = New-Object System.Windows.Forms.Label
$lblImportPath.Location = New-Object System.Drawing.Point(10, 80)
$lblImportPath.Size = New-Object System.Drawing.Size(730, 20)
$lblImportPath.Text = "Schritt 1: Export-Ordner auswaehlen (enthaelt die exportierten Programme):"
$lblImportPath.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$tabImport.Controls.Add($lblImportPath)

$txtImportPath = New-Object System.Windows.Forms.TextBox
$txtImportPath.Location = New-Object System.Drawing.Point(10, 105)
$txtImportPath.Size = New-Object System.Drawing.Size(630, 25)
$tabImport.Controls.Add($txtImportPath)

$btnBrowseImport = New-Object System.Windows.Forms.Button
$btnBrowseImport.Location = New-Object System.Drawing.Point(650, 103)
$btnBrowseImport.Size = New-Object System.Drawing.Size(90, 27)
$btnBrowseImport.Text = "Durchsuchen"
$tabImport.Controls.Add($btnBrowseImport)

# ListView fuer verfuegbare Exporte
$lblAvailable = New-Object System.Windows.Forms.Label
$lblAvailable.Location = New-Object System.Drawing.Point(10, 140)
$lblAvailable.Size = New-Object System.Drawing.Size(730, 20)
$lblAvailable.Text = "Schritt 2: Programm aus der Liste auswaehlen (Klicken Sie auf eine Zeile):"
$lblAvailable.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$tabImport.Controls.Add($lblAvailable)

$listExports = New-Object System.Windows.Forms.ListView
$listExports.Location = New-Object System.Drawing.Point(10, 165)
$listExports.Size = New-Object System.Drawing.Size(730, 130)
$listExports.View = [System.Windows.Forms.View]::Details
$listExports.FullRowSelect = $true
$listExports.GridLines = $true

$listExports.Columns.Add("Programm", 250) | Out-Null
$listExports.Columns.Add("Export-Datum", 150) | Out-Null
$listExports.Columns.Add("Pfad", 330) | Out-Null

$tabImport.Controls.Add($listExports)

# Details
$grpDetails = New-Object System.Windows.Forms.GroupBox
$grpDetails.Location = New-Object System.Drawing.Point(10, 305)
$grpDetails.Size = New-Object System.Drawing.Size(730, 100)
$grpDetails.Text = "Export-Details (wird nach Auswahl angezeigt)"

$txtDetails = New-Object System.Windows.Forms.TextBox
$txtDetails.Location = New-Object System.Drawing.Point(10, 20)
$txtDetails.Size = New-Object System.Drawing.Size(705, 70)
$txtDetails.Multiline = $true
$txtDetails.ScrollBars = "Vertical"
$txtDetails.ReadOnly = $true
$txtDetails.Text = "Waehlen Sie ein Programm aus der Liste oben aus, um Details zu sehen."
$grpDetails.Controls.Add($txtDetails)

$tabImport.Controls.Add($grpDetails)

# Fortschrittsleiste Import
$lblProgressImport = New-Object System.Windows.Forms.Label
$lblProgressImport.Location = New-Object System.Drawing.Point(10, 415)
$lblProgressImport.Size = New-Object System.Drawing.Size(100, 20)
$lblProgressImport.Text = "Fortschritt:"
$tabImport.Controls.Add($lblProgressImport)

$progressImport = New-Object System.Windows.Forms.ProgressBar
$progressImport.Location = New-Object System.Drawing.Point(110, 413)
$progressImport.Size = New-Object System.Drawing.Size(630, 25)
$progressImport.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
$progressImport.Minimum = 0
$progressImport.Maximum = 100
$progressImport.Value = 0
$tabImport.Controls.Add($progressImport)

# Import Optionen
$lblImportAction = New-Object System.Windows.Forms.Label
$lblImportAction.Location = New-Object System.Drawing.Point(10, 450)
$lblImportAction.Size = New-Object System.Drawing.Size(400, 20)
$lblImportAction.Text = "Schritt 3: Aktion auswaehlen:"
$lblImportAction.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$tabImport.Controls.Add($lblImportAction)

# Buttons Import
$btnRefreshExports = New-Object System.Windows.Forms.Button
$btnRefreshExports.Location = New-Object System.Drawing.Point(10, 475)
$btnRefreshExports.Size = New-Object System.Drawing.Size(120, 35)
$btnRefreshExports.Text = "Aktualisieren"
$tabImport.Controls.Add($btnRefreshExports)

$btnImport = New-Object System.Windows.Forms.Button
$btnImport.Location = New-Object System.Drawing.Point(350, 475)
$btnImport.Size = New-Object System.Drawing.Size(200, 35)
$btnImport.Text = "Einstellungen importieren"
$btnImport.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnImport.ForeColor = [System.Drawing.Color]::White
$tabImport.Controls.Add($btnImport)

# Statusleiste Import
$lblStatusImport = New-Object System.Windows.Forms.Label
$lblStatusImport.Location = New-Object System.Drawing.Point(10, 520)
$lblStatusImport.Size = New-Object System.Drawing.Size(730, 40)
$lblStatusImport.Text = "Bereit. Waehlen Sie einen Export aus der Liste."
$tabImport.Controls.Add($lblStatusImport)

# Tabs hinzufuegen
$tabControl.Controls.Add($tabExport)
$tabControl.Controls.Add($tabImport)
$form.Controls.Add($tabControl)

# ============================================
# Event Handler
# ============================================

# Programme laden
function Load-Programs {
    $listPrograms.Items.Clear()
    $lblStatusExport.Text = "Lade installierte Programme..."
    $form.Refresh()
    
    $programs = Get-InstalledPrograms
    
    foreach ($prog in $programs) {
        $item = New-Object System.Windows.Forms.ListViewItem($prog.DisplayName)
        $item.SubItems.Add([string]$(if ($prog.DisplayVersion) { $prog.DisplayVersion } else { "" })) | Out-Null
        $item.SubItems.Add([string]$(if ($prog.Publisher) { $prog.Publisher } else { "" })) | Out-Null
        $item.SubItems.Add([string]$(if ($prog.InstallLocation) { $prog.InstallLocation } else { "" })) | Out-Null
        $item.Tag = $prog
        $listPrograms.Items.Add($item) | Out-Null
    }
    
    $lblStatusExport.Text = "$($listPrograms.Items.Count) Programme gefunden. Waehlen Sie Programme aus und klicken Sie auf 'Ausgewaehlte exportieren'."
}

# Exporte laden
function Load-Exports {
    $listExports.Items.Clear()
    $exportPath = if ($txtImportPath.Text) { $txtImportPath.Text } else { $script:ExportPath }
    
    if (Test-Path $exportPath) {
        $exports = Get-ChildItem -Path $exportPath -Directory
        
        foreach ($export in $exports) {
            $manifestFile = Join-Path $export.FullName "manifest.json"
            if (Test-Path $manifestFile) {
                try {
                    $manifest = Get-Content $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
                    $item = New-Object System.Windows.Forms.ListViewItem($manifest.ProgramName)
                    $item.SubItems.Add($manifest.ExportDate) | Out-Null
                    $item.SubItems.Add($export.FullName) | Out-Null
                    $item.Tag = $export.FullName
                    $listExports.Items.Add($item) | Out-Null
                } catch { }
            }
        }
    }
    
    $lblStatusImport.Text = "$($listExports.Items.Count) Exporte gefunden. Klicken Sie auf ein Programm um es auszuwaehlen."
}

# Suche
$txtSearch.Add_TextChanged({
    $searchText = $txtSearch.Text.ToLower()
    foreach ($item in $listPrograms.Items) {
        if ($searchText -eq "" -or $item.Text.ToLower().Contains($searchText)) {
            $item.ForeColor = [System.Drawing.Color]::Black
        } else {
            $item.ForeColor = [System.Drawing.Color]::LightGray
        }
    }
})

# Durchsuchen Export
$btnBrowseExport.Add_Click({
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Export-Ordner auswaehlen"
    $folderBrowser.SelectedPath = $txtExportPath.Text
    
    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtExportPath.Text = $folderBrowser.SelectedPath
    }
})

# Durchsuchen Import
$btnBrowseImport.Add_Click({
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Waehlen Sie den Ordner mit den exportierten Programmen"
    $folderBrowser.SelectedPath = $script:ExportPath
    
    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtImportPath.Text = $folderBrowser.SelectedPath
        Load-Exports
    }
})

# Aktualisieren
$btnRefresh.Add_Click({ Load-Programs })
$btnRefreshExports.Add_Click({ Load-Exports })

# Alle auswaehlen
$btnSelectAll.Add_Click({
    foreach ($item in $listPrograms.Items) {
        $item.Checked = $true
    }
})

# Keine auswaehlen
$btnDeselectAll.Add_Click({
    foreach ($item in $listPrograms.Items) {
        $item.Checked = $false
    }
})

# Export mit Fortschrittsanzeige
$btnExport.Add_Click({
    $selectedItems = $listPrograms.CheckedItems
    
    if ($selectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Bitte waehlen Sie mindestens ein Programm aus der Liste aus (Checkbox anklicken).", "Keine Auswahl", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    
    $exportPath = $txtExportPath.Text
    New-Item -ItemType Directory -Path $exportPath -Force | Out-Null
    
    $total = $selectedItems.Count
    $current = 0
    
    # Gesamtfortschritt initialisieren
    $progressTotalExport.Maximum = $total
    $progressTotalExport.Value = 0
    $progressExport.Value = 0
    
    # Deaktiviere Buttons waehrend Export
    $btnExport.Enabled = $false
    $btnRefresh.Enabled = $false
    
    foreach ($item in $selectedItems) {
        $current++
        $progName = $item.Text
        $installLoc = $item.SubItems[3].Text
        
        $lblStatusExport.Text = "Exportiere ($current/$total): $progName..."
        $progressTotalExport.Value = $current - 1
        $progressExport.Value = 0
        $form.Refresh()
        
        $result = Export-Program -ProgramName $progName -InstallLocation $installLoc -ExportFolder $exportPath -ProgressBar $progressExport -StatusLabel $lblStatusExport -Form $form
        
        $progressTotalExport.Value = $current
    }
    
    # Reaktiviere Buttons
    $btnExport.Enabled = $true
    $btnRefresh.Enabled = $true
    
    $progressExport.Value = 100
    $progressTotalExport.Value = $total
    $lblStatusExport.Text = "Export abgeschlossen! $total Programme exportiert nach: $exportPath"
    [System.Windows.Forms.MessageBox]::Show("Export erfolgreich abgeschlossen!`n`nExportiert: $total Programme`nOrdner: $exportPath`n`nDurch Multithreading wurde der Export beschleunigt.", "Export fertig", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
})

# Export Details anzeigen
$listExports.Add_SelectedIndexChanged({
    if ($listExports.SelectedItems.Count -gt 0) {
        $selectedPath = $listExports.SelectedItems[0].Tag
        $manifestFile = Join-Path $selectedPath "manifest.json"
        
        if (Test-Path $manifestFile) {
            try {
                $manifest = Get-Content $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
                $details = "AUSGEWAEHLT: $($manifest.ProgramName)`r`n"
                $details += "========================================`r`n"
                $details += "Export-Datum: $($manifest.ExportDate)`r`n"
                $details += "Original-Pfad: $($manifest.InstallLocation)`r`n"
                $details += "Komponenten: $($manifest.Components.Count)`r`n"

                foreach ($comp in $manifest.Components) {
                    $details += "  - $($comp.Type)`r`n"
                }

                if ($manifest.PathEntries -and $manifest.PathEntries.Count -gt 0) {
                    $details += "PATH-Eintraege: $($manifest.PathEntries.Count)`r`n"
                }
                if ($manifest.Services -and $manifest.Services.Count -gt 0) {
                    $details += "Windows-Dienste: $($manifest.Services.Count)`r`n"
                }
                if ($manifest.ScheduledTasks -and $manifest.ScheduledTasks.Count -gt 0) {
                    $details += "Geplante Tasks: $($manifest.ScheduledTasks.Count)`r`n"
                }
                
                $txtDetails.Text = $details
                $lblStatusImport.Text = "Ausgewaehlt: $($manifest.ProgramName) - Klicken Sie auf 'Einstellungen importieren'"
            } catch {
                $txtDetails.Text = "Fehler beim Lesen der Manifest-Datei."
            }
        }
    }
})

# Import mit Fortschrittsanzeige
$btnImport.Add_Click({
    if ($listExports.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Bitte waehlen Sie zuerst ein Programm aus der Liste aus (Klicken Sie auf eine Zeile).", "Keine Auswahl", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    
    $selectedPath = $listExports.SelectedItems[0].Tag
    $progName = $listExports.SelectedItems[0].Text
    
    $confirm = [System.Windows.Forms.MessageBox]::Show("Moechten Sie die Einstellungen von '$progName' wirklich importieren?`n`nHinweis: Dies kann vorhandene Dateien ueberschreiben.", "Import bestaetigen", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    
    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        # Deaktiviere Buttons waehrend Import
        $btnImport.Enabled = $false
        $btnRefreshExports.Enabled = $false
        
        $progressImport.Value = 0
        $lblStatusImport.Text = "Importiere: $progName..."
        $form.Refresh()
        
        $result = Import-Program -ImportFolder $selectedPath -ProgressBar $progressImport -StatusLabel $lblStatusImport -Form $form
        
        # Reaktiviere Buttons
        $btnImport.Enabled = $true
        $btnRefreshExports.Enabled = $true
        
        $progressImport.Value = 100
        $lblStatusImport.Text = $result
        [System.Windows.Forms.MessageBox]::Show("Import abgeschlossen!`n`n$result`n`nDurch Multithreading wurde der Import beschleunigt.", "Import fertig", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
})

# Initial laden
Load-Programs
$txtImportPath.Text = $script:ExportPath
Load-Exports

# Form anzeigen
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
