# Builds the release zip: mge/ with the script, LICENSE, README and the sample assets.
# Unzipped into data/script it gives data/script/mge/mge.lua, loaded with /ls mge/mge.lua.
#
#   powershell -ExecutionPolicy Bypass -File mge/tools/package.ps1            -> data/script/mge.zip
#   powershell -ExecutionPolicy Bypass -File mge/tools/package.ps1 -Out x.zip
#
#   ... -KeepComments                                                            -> the .lua files as they are
#
# What goes in: the files git tracks (as they are in the working tree), minus the developer-only ones
# below, plus $SampleAssets (assets/ is gitignored: converted maps and the user's own exports stay out).
# An untracked .lua file under mge/ stops the build: it would be missing from the zip.
# The tests run first when Lua 5.1 is found, a failure stops the build.
# The .lua files go in without their comments (tools/strip_comments.lua: every line kept, so errors name
# the source's line numbers). Each one is checked: `luac -s` of the original and the stripped file must
# give the same bytes, any difference stops the build.
param(
    [string]$Out,
    [string]$Lua = "$env:LOCALAPPDATA\Programs\Lua51\lua5.1.exe",
    [string]$Luac = "$env:LOCALAPPDATA\Programs\Lua51\luac5.1.exe",
    [switch]$SkipTests,
    [switch]$KeepComments
)
$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot # mge/ (the repo), tools/ is in it
if (-not $Out) { $Out = Join-Path (Split-Path -Parent $repo) "mge.zip" } # next to the repo, in data/script

# tracked, but only for working on MGE
$DevOnly = @("^\.gitignore$", "^docs/", "^tests/", "^tools/")
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
    $untracked = @(git ls-files --others --exclude-standard -- "mge.lua" "mge" | Where-Object { $_ -match "\.lua$" })
    if ($untracked.Count -gt 0) {
        throw "untracked .lua files would be missing from the zip (git add them):`n$($untracked -join "`n")"
    }
    $strip = -not $KeepComments
    if ($strip -and -not ((Test-Path $Lua) -and (Test-Path $Luac))) {
        throw "Lua 5.1 ($Lua, $Luac) is needed to strip comments (-KeepComments to build without)"
    }

    $files = @(git ls-files | Where-Object { $path = $_; -not ($DevOnly | Where-Object { $path -match $_ }) })
    foreach ($asset in $SampleAssets) {
        if (Test-Path $asset) { $files += $asset } else { Write-Warning "sample asset missing: $asset" }
    }
    $files = $files | Sort-Object -Unique

    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $temp = "$Out.tmp"
    if (Test-Path $temp) { Remove-Item $temp -Force }
    # stripped .lua files are written here first, checked, then zipped
    $stage = Join-Path ([System.IO.Path]::GetTempPath()) ("mge-package-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $stage | Out-Null
    $stripped, $before, $after = 0, 0, 0
    $zip = [System.IO.Compression.ZipFile]::Open($temp, "Create")
    try {
        foreach ($file in $files) {
            $source = Join-Path $repo $file
            if ($strip -and $file -match "\.lua$") {
                $staged = Join-Path $stage ($file -replace "[\\/]", "_")
                & $Lua "tools/strip_comments.lua" $source $staged
                if ($LASTEXITCODE -ne 0) { throw "stripping comments failed: $file" }
                # only comments and spacing may differ: the same bytecode without line info
                & $Luac -s -o "$stage\a.luac" $source
                if ($LASTEXITCODE -ne 0) { throw "doesn't compile: $file" }
                & $Luac -s -o "$stage\b.luac" $staged
                if ($LASTEXITCODE -ne 0) { throw "stripped file doesn't compile: $file" }
                $a = [System.IO.File]::ReadAllBytes("$stage\a.luac")
                $b = [System.IO.File]::ReadAllBytes("$stage\b.luac")
                if ([Convert]::ToBase64String($a) -ne [Convert]::ToBase64String($b)) {
                    throw "stripping comments changed the code of $file (tools/strip_comments.lua)"
                }
                $before += (Get-Item $source).Length
                $after += (Get-Item $staged).Length
                $stripped++
                $source = $staged
            }
            # forward slashes: the zip opens the same on every platform
            $entry = "mge/" + ($file -replace "\\", "/")
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $source, $entry, "Optimal")
        }
    } finally {
        $zip.Dispose()
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
    Move-Item $temp $Out -Force
    $size = [math]::Round((Get-Item $Out).Length / 1KB)
    Write-Host "wrote $Out ($($files.Count) files, $size KB)"
    if ($strip) {
        Write-Host ("comments stripped from {0} .lua files: {1} KB -> {2} KB, code checked unchanged" -f `
            $stripped, [math]::Round($before / 1KB), [math]::Round($after / 1KB))
    }
} finally {
    Pop-Location
}
