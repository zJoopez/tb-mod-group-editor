# Builds the release zip: mge/ with the script, LICENSE, README, tools/mapconv.lua and the sample
# assets. Unzipped into data/script it gives data/script/mge/mge.lua, loaded with /ls mge/mge.lua.
#
#   powershell -ExecutionPolicy Bypass -File mge/tools/package.ps1            -> data/script/mge.zip
#   powershell -ExecutionPolicy Bypass -File mge/tools/package.ps1 -Out x.zip
#
# What goes in: the files git tracks (as they are in the working tree), minus the developer-only ones
# below, plus $SampleAssets (assets/ is gitignored: converted maps and the user's own exports stay out).
# The tests run first when Lua 5.1 is found, a failure stops the build.
param(
    [string]$Out,
    [string]$Lua = "$env:LOCALAPPDATA\Programs\Lua51\lua5.1.exe",
    [switch]$SkipTests
)
$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot # mge/ (the repo), tools/ is in it
if (-not $Out) { $Out = Join-Path (Split-Path -Parent $repo) "mge.zip" } # next to the repo, in data/script

# tracked, but only for working on MGE
$DevOnly = @("^\.gitignore$", "^docs/", "^tests/", "^tools/package\.ps1$")
# examples shipped with the release (assets/ isn't tracked)
$SampleAssets = @(
    "mge/assets/obj/force.tbm", "mge/assets/obj/katana.tbm", "mge/assets/obj/pins.tbm",
    "mge/assets/obj/scooter.tbm", "mge/assets/player/car.tbm", "mge/assets/player/fat.tbm",
    "mge/assets/atmo/pillars.atmo" # also makes the folder Export writes atmo pieces to
)

Push-Location $repo
try {
    if (-not $SkipTests) {
        if (Test-Path $Lua) {
            & $Lua "tests/run.lua"
            if ($LASTEXITCODE -ne 0) { throw "tests failed, nothing packaged (-SkipTests to build anyway)" }
        } else {
            Write-Warning "Lua 5.1 not found at $Lua, tests skipped"
        }
    }

    $dirty = git status --porcelain --untracked-files=no
    if ($dirty) { Write-Warning "uncommitted changes go into the zip:`n$($dirty -join "`n")" }

    $files = @(git ls-files | Where-Object { $path = $_; -not ($DevOnly | Where-Object { $path -match $_ }) })
    foreach ($asset in $SampleAssets) {
        if (Test-Path $asset) { $files += $asset } else { Write-Warning "sample asset missing: $asset" }
    }
    $files = $files | Sort-Object -Unique

    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $temp = "$Out.tmp"
    if (Test-Path $temp) { Remove-Item $temp -Force }
    $zip = [System.IO.Compression.ZipFile]::Open($temp, "Create")
    try {
        foreach ($file in $files) {
            # forward slashes: the zip opens the same on every platform
            $entry = "mge/" + ($file -replace "\\", "/")
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, (Join-Path $repo $file), $entry, "Optimal")
        }
    } finally {
        $zip.Dispose()
    }
    Move-Item $temp $Out -Force
    $size = [math]::Round((Get-Item $Out).Length / 1KB)
    Write-Host "wrote $Out ($($files.Count) files, $size KB)"
} finally {
    Pop-Location
}
