##############################################################################
#
# File mushware/build_dll.ps1
#
# Copyright: Andy Southgate 2020
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.
#
##############################################################################

Param(
    [Parameter(Mandatory)]$Configuration,
    [Parameter(Mandatory)]$BuildNumber,
    [Parameter(Mandatory=$false)][Switch]$InstallMissing
)

Set-StrictMode -Version 3.0

$ErrorActionPreference = "Stop"

If ($BuildNumber) {
    If ($BuildNumber -as [int] -gt 65534) {
        Throw "Build number too large"
    }
    $Version = "2.8.0.$BuildNumber"
    If ($env:TRAVIS_TAG) {
        If ($env:TRAVIS_TAG -match "^v(\d+\.\d+\.\d+)(-\d+)?$") {
            $Version = "$($matches[1]).$BuildNumber"
        } Else {
            Write-Error "Badly formed or non-release git tag ""$($env:TRAVIS_TAG)"""
        }
    } else {
    }
} Else {
    $Version = "0.0.0.0"
}

Write-Host -ForegroundColor Blue @"
*
*
* Beginning Ruby DLL $Configuration build for version $Version.
*
*
"@

Write-Host "Environment is:"
Get-ChildItem env:* | Sort-Object Name

Write-Host "Path is:"
Get-ChildItem env:PATH | ForEach-Object { $_.Value.Split(';') }

If ($Configuration -eq "") {
    Write-Host "Configuration not supplied so using Debug"
    $Configuration = "Debug"
}

if ($PSScriptRoot) {
    $ProjectRoot = $(Join-Path -Resolve $PSScriptRoot -ChildPath "..")
} Else {
    $ProjectRoot = $(Join-Path -Resolve $pwd -ChildPath "..")
}
$RubyBuildRoot = $ProjectRoot
Set-Location $RubyBuildRoot

$buildtools_root="C:\Program Files (x86)\Microsoft Visual Studio 14.0\VC\bin\amd64"
$msbuild_root="C:\Program Files (x86)\Microsoft Visual Studio\2017\BuildTools\MSBuild\15.0\Bin"
$msys_root="C:\tools\msys64\usr\bin"
$signtool_root="C:\Program Files (x86)\Windows Kits\10\bin\10.0.18362.0\x86"

$env:PATH = "$buildtools_root;$msbuild_root;$msys_root;$signtool_root;$env:PATH"

Write-Host "Path for build is:"
Get-ChildItem env:PATH | ForEach-Object { $_.Value.Split(';') }

Write-Host -ForegroundColor DarkCyan @"

********************************************
*                                          *
*    Assembling dependencies               *
*                                          *
********************************************

"@

Set-Location $RubyBuildRoot

If (Test-Path $msys_root) {
    Write-Host "MSYS already installed."
} Else {
    cinst --no-progress --version=20200720.0.0 -y msys2
}

pacman --noconfirm --sync autoconf=2.69-5
pacman --noconfirm --sync bison=3.6.4-1
pacman --noconfirm --sync patch=2.7.6-1
pacman --noconfirm --sync ruby=2.7.1-1

Write-Host -ForegroundColor DarkCyan @"

**************************************
*                                    *
*    Starting Ruby DLL main build    *
*                                    *
**************************************

"@

Set-Location $buildtools_root
cmd.exe /C"CALL vcvars64.bat && set > %temp%\vcvars.txt"

Get-Content "$env:temp\vcvars.txt" | Foreach-Object {
  if ($_ -match "^(.*?)=(.*)$") {
    Set-Content "env:\$($matches[1])" $matches[2]
  }
}

$env:PATH = "$buildtools_root;$msbuild_root;$msys_root;$signtool_root;$env:PATH"

Set-Location $RubyBuildRoot

$configure_args = @("--disable-install-doc", "--disable-rubygems", "--target=x64-mswin64", "--with-baseruby=${msys_root}/ruby", "--with-git=")
If ($Configuration -eq "Debug") {
    $configure_args += "--with-debug-env"
}
win32/configure.bat $configure_args

$build_process = Start-Process -NoNewWindow -PassThru -FilePath "nmake.exe" -ArgumentList "miniruby.exe", ".rbconfig.time", "lib", "dll"
$handle = $build_process.Handle # Fix for missing ExitCode
$build_process.WaitForExit()

if ($build_process.ExitCode -ne 0) {
    Throw "Build failed failed ($($build_process.ExitCode))"
}

Write-Host -ForegroundColor Green @"

**************************
*                        *
*    BUILD SUCCESSFUL    *
*                        *
**************************

"@

$dll_root = "dll"
$underscore_version = $Version.Replace(".", "_")

# Copy generated config.h into include directory
(Get-Content ".ext\include\x64-mswin64_140\ruby\config.h") -replace "#error","// #error" | Set-Content -Force "include\ruby\config.h"

New-Item -ItemType "directory" -Path $dll_root -Force | Foreach-Object { "Created directory $($_.FullName)" }
Move-Item -Force x64-vcruntime140-ruby280.dll $dll_root
Move-Item -Force x64-vcruntime140-ruby280.lib $dll_root
Move-Item -Force x64-vcruntime140-ruby280.pdb $dll_root
Get-FileHash $dll_root/* -Algorithm SHA256 | Format-List
Compress-Archive -Path include,$dll_root -DestinationPath MushRuby_${Configuration}_${underscore_version}.zip

Write-Host -ForegroundColor Blue "$Configuration build complete for Mushware Ruby DLL version $Version"
