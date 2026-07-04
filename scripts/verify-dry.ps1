$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$adapterPath = Join-Path $root 'src/matlab_polycall.c'
$mexPath = Join-Path $root 'src/matlab_polycall_mex.c'
$matlabPaths = @(
    (Join-Path $root 'src/+obinexus/+polycall/runConfig.m'),
    (Join-Path $root 'src/+obinexus/+polycall/runConfigOrError.m')
)
$sourcePaths = @($adapterPath, $mexPath) + $matlabPaths
$forbidden = 'fopen|open\(|CreateFile|sscanf|strtok|socket\(|connect\('
$matches = Select-String -Path $sourcePaths -Pattern $forbidden

if ($matches) {
    $matches | ForEach-Object { Write-Error $_.Line }
    throw 'matlab-polycall must not parse configuration or implement runtime logic'
}

$adapter = Get-Content -Raw $adapterPath
$mex = Get-Content -Raw $mexPath
if (-not $adapter.Contains('polycall_ffi_run_config(config_path, 1)')) {
    throw 'matlab-polycall does not forward through polycall_ffi_run_config'
}
if (-not $mex.Contains('mxArrayToUTF8String') -or
    -not $mex.Contains('mxFree(config_path)')) {
    throw 'matlab-polycall does not safely marshal the MATLAB path'
}
if (-not $mex.Contains('mxINT32_CLASS')) {
    throw 'matlab-polycall does not return a MATLAB int32 status'
}

Write-Output 'matlab-polycall thin-adapter check: PASS'
