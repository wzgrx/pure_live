function Resolve-PureLiveSubstPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [string[]] $Mappings = @()
    )

    $resolved = [IO.Path]::GetFullPath($Path)
    $visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    while ($true) {
        $root = [IO.Path]::GetPathRoot($resolved).TrimEnd('\')
        if (-not $visited.Add($root)) { throw "Cyclic SUBST mapping for $Path" }
        $target = @($Mappings | ForEach-Object {
            if ($_ -match "^$([Regex]::Escape($root))\\:\s*=>\s*(.+)$") {
                $Matches[1].Trim()
            }
        })
        if ($target.Count -eq 0) { return $resolved }
        if ($target.Count -ne 1) { throw "Ambiguous SUBST mapping for $root" }
        $relative = $resolved.Substring([IO.Path]::GetPathRoot($resolved).Length)
        $resolved = [IO.Path]::GetFullPath([IO.Path]::Combine($target[0], $relative))
    }
}
