# ipadecrypt desktop helper for a locally owned IPA.
# Nothing here uploads the IPA or your Apple account information to GitHub.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $IpaPath,
    [string] $CliPath = '',
    [string] $OutputPath = ''
)
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $IpaPath).Path
if ([IO.Path]::GetExtension($source) -ine '.ipa') {
    throw 'Input must be an .ipa file.'
}
if ([string]::IsNullOrWhiteSpace($CliPath)) {
    $CliPath = Join-Path $PSScriptRoot 'ipadecrypt.exe'
}
$cli = (Resolve-Path -LiteralPath $CliPath).Path
if (-not (Test-Path -LiteralPath $cli -PathType Leaf)) {
    throw "ipadecrypt CLI executable is missing at $cli"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path ([IO.Path]::GetDirectoryName($source)) (([IO.Path]::GetFileNameWithoutExtension($source)) + '-decrypted.ipa')
}
$fullOutput = [IO.Path]::GetFullPath($OutputPath)
if ([IO.Path]::GetFullPath($source) -ieq $fullOutput) {
    throw 'Output must differ from the original IPA.'
}
if (Test-Path -LiteralPath $fullOutput) {
    throw "Refusing to overwrite existing file: $fullOutput"
}
Write-Host 'Using the upstream ipadecrypt console.'
Write-Host 'Requires a credential previously minted from your own jailbroken device using: ipadecrypt bootstrap'
& $cli --redact decrypt $source --output $fullOutput --no-on-device --extra-verify
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $fullOutput -PathType Leaf)) {
    throw 'Decryption did not produce a verified IPA. Run ipadecrypt bootstrap locally first, or inspect the error above.'
}
$size = (Get-Item -LiteralPath $fullOutput).Length
if ($size -lt 1024) {
    throw 'The output IPA is unexpectedly small. Do not install it.'
}
$hash = Get-FileHash -LiteralPath $fullOutput -Algorithm SHA256
Write-Host "Produced: $fullOutput"
Write-Host "Size: $size bytes; SHA256: $($hash.Hash)"
Write-Host 'This IPA still needs a new valid signing certificate before installation.'
