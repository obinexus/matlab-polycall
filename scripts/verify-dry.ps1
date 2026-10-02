$ErrorActionPreference = 'Stop'

# Boundary check (PowerShell twin of verify-dry.sh).
$root = Split-Path -Parent $PSScriptRoot
$layer = Get-Content -Raw (Join-Path $root 'src/matlab_polycall.c')
$mex = Get-Content -Raw (Join-Path $root 'src/matlab_polycall_mex.c')
$header = Get-Content -Raw (Join-Path $root 'include/matlab_polycall.h')

foreach ($text in @($layer, $mex)) {
    if ($text -match 'fopen|CreateFile|sscanf|strtok|socket\(|connect\(') {
        throw 'matlab-polycall must not parse configuration or implement runtime logic'
    }
}
if (-not $header.Contains('#include <polycall.h>')) { throw 'the C layer must include <polycall.h>' }
if (-not $layer.Contains('polycall_ffi_run_config(config_path, 1)')) { throw 'runConfig must forward to polycall_ffi_run_config(path, 1)' }
if (-not $layer.Contains('polycall_ffi_abi_version()')) { throw 'the ABI version must be checked' }
if (-not $mex.Contains('mxArrayToUTF8String')) { throw 'paths must be converted as UTF-8' }
if (Test-Path (Join-Path $root 'generated/polycall/polycall_ffi.h')) { throw 'stub header must not exist' }
Write-Output 'matlab-polycall thin-adapter check: PASS'
