# Creature web export (repo root). Uses the console Godot binary so export logs are visible.
# Boot splash source: loading_splash2.jpg (converted to loading_splash2.png for Godot).
# Close any app that has those images open before running.

$ErrorActionPreference = "Stop"
$Godot = "C:\godot47\Godot_v4.7-stable_win64_console.exe"
$Project = $PSScriptRoot
$OutHtml = Join-Path $Project "..\index.html"
$SplashJpg = Join-Path $Project "loading_splash2.jpg"
$SplashPng = Join-Path $Project "loading_splash2.png"

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
			Write-Host "Splash file locked (attempt $i/$Attempts) - close Godot image preview or other apps using it."
			Start-Sleep -Seconds 2
		}
	}
	return $false
}

function Convert-JpgToPng([string]$JpgPath, [string]$PngPath) {
	Add-Type -AssemblyName System.Drawing
	$img = [System.Drawing.Image]::FromFile($JpgPath)
	try {
		$img.Save($PngPath, [System.Drawing.Imaging.ImageFormat]::Png)
	} finally {
		$img.Dispose()
	}
}

if (-not (Test-Path $SplashJpg)) {
	Write-Error "Missing $SplashJpg - save your splash art there and retry."
}
if (-not (Wait-ReadableFile $SplashJpg)) {
	Write-Error "Cannot read $SplashJpg - unlock the file and retry."
}

Write-Host "Converting loading_splash2.jpg -> loading_splash2.png for Godot boot splash..."
Convert-JpgToPng $SplashJpg $SplashPng

& $Godot --headless --path $Project --import
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Godot --headless --path $Project --export-release "Web" $OutHtml
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Web shell loads index.png; JPEG bytes keep the deploy smaller than a full PNG.
$OutPng = Join-Path (Split-Path $OutHtml) "index.png"
Copy-Item $SplashJpg $OutPng -Force
Write-Host "Exported to $(Split-Path $OutHtml) (index.png from loading_splash2.jpg, $((Get-Item $OutPng).Length) bytes)"
