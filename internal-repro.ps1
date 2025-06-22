Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$global:ProgressPreference = "SilentlyContinue"
#requires -Version 5.1

function _kill($ProcessName) {
    try {
        & cmd /c "taskkill /T /F /IM ${processName} > nul 2>&1"
        Write-Host "Killed (if running): $($ProcessName)"
    }
    catch {
        Write-Host "Failed to kill ${processName}: $_"
    }
}

function _killProcs {
    Write-Host -ForegroundColor Yellow -Object "
----------------------------
Cleaning up running processes
----------------------------
    "
    _kill dotnet.exe
    _kill vbcscompiler.exe
    _kill vctip.exe
    _kill msbuild.exe
    _kill sqlpackage.exe

    Write-Host -ForegroundColor Yellow -Object "
-----------------------------------
DONE: Cleaning up running processes
-----------------------------------
    "
}

Clear-Host
_killProcs


$DotnetUrl = "https://download.visualstudio.microsoft.com/download/pr/c5650c11-6944-488c-9192-cbab3c199deb/059197c7e46969164e752eec107fbea1/dotnet-sdk-9.0.100-win-x64.zip"
if (-Not (Test-Path -Path "dotnet.zip")) {
    Write-Host "Downloading dotnet SDK binaries ..."
    Invoke-WebRequest -Uri $DotnetUrl -OutFile "dotnet.zip"
    Write-Host "Done"
}

if (-Not (Test-Path -Path "dotnet")) {
    Expand-Archive -Path "dotnet.zip" -DestinationPath "dotnet" -Force
}

$SqlPackageWinUrl = "https://aka.ms/sqlpackage-windows"
if (-Not (Test-Path -Path "sqlpackage.zip")) {
    Write-Host "Downloading sqlpackage binaries ..."
    Invoke-WebRequest -Uri $SqlPackageWinUrl -OutFile "sqlpackage.zip"
    Write-Host "Done"
}

if (-Not (Test-Path -Path "sqlpackage")) {
    Expand-Archive -Path "sqlpackage.zip" -DestinationPath "sqlpackage" -Force
}

$VsWherePath = Join-Path -Path $(${Env:ProgramFiles(x86)}) -ChildPath "Microsoft Visual Studio"
$VsWherePath = Join-path -Path $VsWherePath -ChildPath "Installer"
$VsWherePath = Join-Path -Path $VsWherePath -ChildPath "vswhere.exe"

$MsBuildExePath = & $VsWherePath -latest -requires "Microsoft.Component.MSBuild" -find "MSBuild\**\Bin\amd64\MSBuild.exe"
if (-Not $MsBuildExePath) {
    $MsBuildExePath = & $VsWherePath -latest -requires "Microsoft.Component.MSBuild" -find "MSBuild\**\Bin\MSBuild.exe"
}
$MsBuildExePath = Resolve-Path -Path $MsBuildExePath
$MsBuildPath = Split-Path -Path $MsBuildExePath -Parent
$MsBuildPath = Resolve-Path -Path $MsBuildPath

$DotnetPath = Join-Path -Path $PSScriptRoot -ChildPath "dotnet"
$DotnetPath = Resolve-Path -Path $DotnetPath
$DotnetExePath = Join-Path -Path $DotnetPath -ChildPath "dotnet.exe"
$DotnetExePath = Resolve-Path -Path $DotnetExePath

$SqlPackagePath = Join-Path -Path $PSScriptRoot -ChildPath "sqlpackage"
$SqlPackagePath = Resolve-Path -Path $SqlPackagePath
$SqlPackageExePath = Join-Path -Path $SqlPackagePath -ChildPath "sqlpackage.exe"
$SqlPackageExePath = Resolve-Path -Path $SqlPackageExePath

$CsProjPath = Join-Path -Path $PSScriptRoot -ChildPath "MyContributor"
$CsProjPath = Join-Path -Path $CsProjPath -ChildPath "MyContributor.csproj"
$CsProjPath = Resolve-Path -Path $CsProjPath

$SqlProjPath = Join-Path -Path $PSScriptRoot -ChildPath "ReproDB"
$SqlProjPath = Join-Path -Path $SqlProjPath -ChildPath "ReproDB.sqlproj"
$SqlProjPath = Resolve-Path -Path $SqlProjPath

$SystemRootPath = $Env:SystemRoot
$System32Path = Join-Path -Path $SystemRootPath -ChildPath "system32"

$Env:PATH = ""
$Env:PATH += "$($System32Path);"
$Env:PATH += "$($DotnetPath);"
$Env:PATH += "$($MsBuildPath);"
$Env:PATH += "$($SqlPackagePath);"

Write-Host -ForegroundColor Yellow -Object "
------------------------------
REPRO SCRIPT EXECUTION DETAILS

MSBuild version: $(& msbuild /version)
SqlPackage version: $(& sqlpackage /version)
Dotnet version: $(& dotnet --version)

PATH environment variable:
$($Env:PATH)
------------------------------
"

dotnet build -c Release $CsProjPath
dotnet publish $CsProjPath

$MsBuildArgs = @(
    "-nologo"
    "-verbosity:minimal"
    "-target:Clean;Rebuild"
    "-property:Configuration=Release"
    "$($SqlProjPath)"
)

msbuild $MsBuildArgs

$ContributorFolderPath = Join-Path -Path $PSScriptRoot -ChildPath "MyContributor"
$ContributorFolderPath = Join-Path -Path $ContributorFolderPath -ChildPath "bin"
$ContributorFolderPath = Join-Path -Path $ContributorFolderPath -ChildPath "Debug"
$ContributorFolderPath = Join-Path -Path $ContributorFolderPath -ChildPath "netstandard2.1"
$ContributorFolderPath = Join-Path -Path $ContributorFolderPath -ChildPath "publish"
$ContributorFolderPath = Resolve-Path -Path $ContributorFolderPath

$DacpacPath = Resolve-Path -Path ".\ReproDB\bin\Release\ReproDB.dacpac"

$OutPath = Join-Path -Path $PSScriptRoot -ChildPath "out"
New-Item -Type Directory -Name "out" -Force -ErrorAction SilentlyContinue | Out-Null
$OutPath = Resolve-Path -Path $OutPath

$ScriptPath = Join-Path -Path $OutPath -ChildPath ".\Script.sql"
$ReportPath = Join-Path -Path $OutPath -ChildPath ".\Report.xml"

# Cleanup MyContributor.dll from the sqlpackage folder (allows this repro to run idempotently)
$SqlPackageFolderContributorDllPath = Join-Path -Path $SqlPackagePath -ChildPath "MyContributor.dll"
if (Test-Path -Path $SqlPackageFolderContributorDllPath) {
    Remove-Item -Path $SqlPackageFolderContributorDllPath -Force -ErrorAction Stop | Out-Null
}

# THIS FAILS
$SqlPackageArgs = @(
    "/a:script"
    "/drp:$($ReportPath)"
    "/dsp:$($ScriptPath)"
    "/of:True"
    "/sf:$($DacpacPath)"
    "/tf:$($DacpacPath)"
    "/tdn:MyDB"
    "/p:AdditionalDeploymentContributorPaths=$($ContributorFolderPath)"
    "/p:AdditionalDeploymentContributors=MyDeploymentContributor"
)

Write-Host -ForegroundColor Red -Object "
-----------------------------
Expect this execution to FAIL
-----------------------------
"

& cmd /c "$($SqlPackageExePath) $($SqlPackageArgs) 2>&1"

Write-Host -ForegroundColor Red -Object "
------------------------
END OF FAILING EXECUTION
------------------------
"

# THIS WORKS
$ContributorDllPath = Join-Path -Path $ContributorFolderPath -ChildPath "MyContributor.dll"
Copy-Item -Path $ContributorDllPath -Destination $SqlPackagePath

$SqlPackageArgs = @(
    "/a:script"
    "/drp:$($ReportPath)"
    "/dsp:$($ScriptPath)"
    "/of:True"
    "/sf:$($DacpacPath)"
    "/tf:$($DacpacPath)"
    "/tdn:MyDB"
    "/p:AdditionalDeploymentContributors=MyDeploymentContributor"
)

Write-Host -ForegroundColor Green -Object "
-----------------------------------------------------------------
Expect this execution to PASS
Expect to see 'Hello world' written to console by the contributor
-----------------------------------------------------------------
"

& cmd /c "$($SqlPackageExePath) $($SqlPackageArgs) 2>&1"

Write-Host -ForegroundColor Green -Object "
------------------------
END OF PASSING EXECUTION
------------------------
"

_killProcs
