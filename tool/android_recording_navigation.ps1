# Pure helpers. Loading this file performs no device discovery or commands.
function Get-RecordingForegroundPackage {
    param([AllowEmptyString()][string] $ActivityDump)
    # Prefer top-resumed over a lower resumed activity on multi-window devices.
    # An explicit null top-resumed state is not permission to use an older row.
    $rows = @($ActivityDump -split '\r?\n' | Where-Object { $_ -match '^\s*topResumedActivity\s*=' })
    if ($rows.Count -eq 0) {
        $rows = @($ActivityDump -split '\r?\n' | Where-Object { $_ -match '^\s*mResumedActivity\s*[:=]' })
    }
    if ($rows.Count -ne 1) { return '' }
    if ($rows[0] -match '\bActivityRecord\{[^}\r\n]*\su0\s+(?<package>[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+)/[^\s}]+') {
        return $Matches['package']
    }
    return ''
}

function Get-RecordingPlatformTabs {
    param(
        [Parameter(Mandatory = $true)][string] $Xml,
        [Parameter(Mandatory = $true)][string[]] $KnownLabels
    )
    [xml]$document = $Xml
    $tabs = @($document.SelectNodes('//node') | ForEach-Object {
        if ($_.GetAttribute('enabled') -ne 'true' -or $_.GetAttribute('clickable') -ne 'true') { return }
        $label = $_.GetAttribute('content-desc')
        if ([string]::IsNullOrWhiteSpace($label)) { $label = $_.GetAttribute('text') }
        $ordinal = [regex]::Match($label, '^(.+?)[\r\n]+(?:第\s*(\d+)\s*个标签，共\s*(\d+)\s*个|Tab\s+(\d+)\s+of\s+(\d+))$')
        if (-not $ordinal.Success -or $ordinal.Groups[1].Value -cnotin $KnownLabels) { return }
        $index = if ($ordinal.Groups[2].Success) { [int]$ordinal.Groups[2].Value } else { [int]$ordinal.Groups[4].Value }
        $total = if ($ordinal.Groups[3].Success) { [int]$ordinal.Groups[3].Value } else { [int]$ordinal.Groups[5].Value }
        if ($index -lt 1 -or $total -lt $index) { return }
        if ($_.GetAttribute('bounds') -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { return }
        $left = [int]$Matches[1]; $top = [int]$Matches[2]
        $right = [int]$Matches[3]; $bottom = [int]$Matches[4]
        if ($right -le $left -or $bottom -le $top) { return }
        [pscustomobject]@{
            Label = $ordinal.Groups[1].Value; Index = $index; Total = $total
            Left = $left; Top = $top; Right = $right; Bottom = $bottom
            Selected = $_.GetAttribute('selected') -eq 'true'
        }
    })
    if ($tabs.Count -eq 0) { throw 'No visible platform tab semantics were found.' }
    $rows = @($tabs | Group-Object { "$($_.Top):$($_.Bottom):$($_.Total)" })
    if ($rows.Count -ne 1 -or @($tabs | Group-Object Label | Where-Object Count -gt 1).Count -gt 0) {
        throw 'Platform tab semantics are ambiguous; no gesture was selected.'
    }
    $tabs | Sort-Object Left
}
