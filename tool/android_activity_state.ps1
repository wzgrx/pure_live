# Pure parsing helpers: sourcing this file never connects to a device.
function Test-AndroidTargetPictureInPicture {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $ActivityDump,
        [string] $Package = 'com.mystyle.purelive'
    )

    # Scope the reported state to one ActivityRecord, not the whole device.
    # supportsPictureInPicture is a capability, not evidence of entering PiP.
    $blocks = [regex]::Matches(
        $ActivityDump,
        '(?ms)^\s*\*\s*Hist\s+#\d+:\s*ActivityRecord\{(?<identity>[^\r\n]*)\}\r?\n(?<state>.*?)(?=^\s*\*\s*(?:Hist|Task)\b|\z)'
    )
    $target = '(?:^|\s)' + [regex]::Escape($Package) + '/[^\s}]+'
    foreach ($block in $blocks) {
        if ($block.Groups['identity'].Value -match $target -and
            $block.Groups['state'].Value -match '\bmLastReportedPictureInPictureMode=true\b') {
            return $true
        }
    }
    return $false
}
