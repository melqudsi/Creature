# Creature web export (repo root). Uses the console Godot binary so export logs are visible.
# Boot splash: loading_splash1.png (Project Settings → Boot Splash). Close any app
# that has that PNG open (Godot image preview, Photos, etc.) before running.

$ErrorActionPreference = "Stop"
$Godot = "C:\godot47\Godot_v4.7-stable_win64_console.exe"
$Project = $PSScriptRoot
$OutHtml = Join-Path $Project "..\index.html"
$Splash = Join-Path $Project "loading_splash1.png"

if (-not (Test-Path $Godot)) {
	Write-Error "Godot not found at $Godot"
}

function Wait-ReadableFile([string]$Path, [int]$Attempts = 10) {
	for ($i = 1; $i -le $Attempts; $i++) {
		try {
			$fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
			$fs.Close()
			return $true
		} catch {
			Write-Host "Splash file locked (attempt $i/$Attempts) — close Godot's PNG preview or other apps using it."
			Start-Sleep -Seconds 2
		}
	}
	return $false
}

if (-not (Wait-ReadableFile $Splash)) {
	Write-Error "Cannot read $Splash — unlock the file and retry."
}

& $Godot --headless --path $Project --import
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Godot --headless --path $Project --export-release "Web" $OutHtml
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Ensure the web loader uses the custom art (Godot writes index.png from boot splash).
$OutPng = Join-Path (Split-Path $OutHtml) "index.png"
Copy-Item $Splash $OutPng -Force
Write-Host "Exported to $(Split-Path $OutHtml) (index.png = loading_splash1.png, $((Get-Item $OutPng).Length) bytes)"
