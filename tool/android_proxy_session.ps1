# Sourcing this helper never contacts Android. IO is bound to one context.
function Initialize-ProxyContext {
    param([string]$Serial, $AdbExecutable, [string]$EvidenceDirectory)
    if ([string]::IsNullOrWhiteSpace($Serial)) { throw 'An explicit proxy Serial is required.' }
    $script:ProxyContext = @{
        Serial=$Serial; Adb=$AdbExecutable; Evidence=$EvidenceDirectory
        Package='com.mystyle.purelive'; HomePackage=''; ForegroundLost=$false; Sequence=0; ActionSequence=0
    }
    $model = ((Invoke-ProxyAdb @('shell','getprop','ro.product.model')) -join '').Trim()
    $device = ((Invoke-ProxyAdb @('shell','getprop','ro.product.device')) -join '').Trim()
    if ($model -cne '25102RKBEC' -or $device -cne 'myron') { throw 'Proxy target model/device mismatch.' }
}

function Invoke-ProxyAdb {
    param([string[]]$Arguments, [switch]$AllowHome)
    if ($Arguments.Count -ge 2 -and $Arguments[0] -eq 'shell' -and (
        $Arguments[1] -in @('input','uiautomator','screencap','monkey') -or
        ($Arguments[1] -eq 'wm' -and $Arguments[2] -eq 'dismiss-keyguard') -or
        ($Arguments[1] -eq 'am' -and $Arguments[2] -eq 'start'))) {
        Assert-ProxyForeground -AllowHome:$AllowHome
    }
    $output = & $script:ProxyContext.Adb -s $script:ProxyContext.Serial @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($Arguments[0] -eq 'shell') { $script:ProxyContext.ForegroundLost=$true }
        throw "Proxy ADB command failed ($LASTEXITCODE): $($Arguments -join ' ')`n$($output -join "`n")"
    }
    @($output)
}

function Assert-ProxyForeground {
    param([switch]$AllowHome)
    if ($script:ProxyContext.ForegroundLost) { throw 'Proxy UI was interrupted; no more UI input in this invocation.' }
    $dump = (Invoke-ProxyAdb @('shell','dumpsys','activity','activities')) -join "`n"
    $current = Get-RecordingForegroundPackage $dump
    if ($current -ceq $script:ProxyContext.Package) { return }
    if ($AllowHome -and $script:ProxyContext.HomePackage -and $current -ceq $script:ProxyContext.HomePackage) { return }
    $script:ProxyContext.ForegroundLost = $true
    throw "Proxy target foreground changed or is unknown (observed='$current')."
}

function Get-ProxyUiDocument {
    $script:ProxyContext.Sequence++
    $name = 'proxy-ui-' + $script:ProxyContext.Sequence
    $remote = "/sdcard/purelive-proxy-$PID-$name.xml"
    $local = Join-Path $script:ProxyContext.Evidence "$name.xml"
    try {
        $output = (Invoke-ProxyAdb @('shell','uiautomator','dump','--compressed',$remote)) -join "`n"
        if ($output -match '(?i)error|exception') { throw 'Proxy UI dump did not succeed.' }
        Invoke-ProxyAdb @('pull',$remote,$local) | Out-Null
        Assert-ProxyForeground
        [xml](Get-Content -LiteralPath $local -Raw -Encoding utf8)
    } finally {
        try { Invoke-ProxyAdb @('shell','rm','-f',$remote) | Out-Null } catch {}
    }
}

function Get-ProxyBounds {
    param([string]$Bounds,[switch]$AllowEmpty)
    if ($Bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { throw 'Invalid proxy UI bounds.' }
    $left=[int]$Matches[1]; $top=[int]$Matches[2]; $right=[int]$Matches[3]; $bottom=[int]$Matches[4]
    if ($right -lt $left -or $bottom -lt $top -or
        (-not $AllowEmpty -and ($right -eq $left -or $bottom -eq $top))) { throw 'Empty proxy UI bounds.' }
    @{Left=$left;Top=$top;Right=$right;Bottom=$bottom}
}

function Find-ProxyNode {
    param([xml]$Document,[string]$Title,[switch]$Switch)
    $nodes = @($Document.SelectNodes('//node') | Where-Object {
        $label = $_.GetAttribute('content-desc')
        if (-not $label) { $label=$_.GetAttribute('text') }
        $first = ($label -split '\r?\n')[0]
        $first -ceq $Title -and $_.GetAttribute('enabled') -eq 'true' -and
        $_.GetAttribute('clickable') -eq 'true' -and
        (-not $Switch -or ($_.GetAttribute('checkable') -eq 'true' -and $_.GetAttribute('checked') -in @('true','false')))
    })
    if ($nodes.Count -gt 1) { throw "Ambiguous proxy UI label: $Title" }
    if ($nodes.Count -eq 1) {
        $bounds = Get-ProxyBounds $nodes[0].GetAttribute('bounds')
        [pscustomobject]@{Node=$nodes[0];Bounds=$bounds;Checked=($nodes[0].GetAttribute('checked') -eq 'true')}
    }
}

function Get-ProxyTapPoint {
    param($Node)
    $b=$Node.Bounds
    # Accessibility drawing-order is not a reliable Flutter hit-test order.
    # Conservatively exclude every unrelated enabled clickable rectangle, even
    # if it might be behind the target. Never close or drag the floating player.
    $margin=8
    $regions=@(@{Left=$b.Left+$margin;Top=$b.Top+$margin;Right=$b.Right-$margin;Bottom=$b.Bottom-$margin})
    if($regions[0].Right-$regions[0].Left -lt 16 -or $regions[0].Bottom-$regions[0].Top -lt 16){
        throw 'Proxy control has no usable interior hit region.'
    }
    $excluded=0
    foreach($other in $Node.Node.OwnerDocument.SelectNodes('//node[@enabled="true" and @clickable="true"]')){
        $ancestor=$Node.Node; $isAncestor=$false
        while($null -ne $ancestor){
            if([object]::ReferenceEquals($ancestor,$other)){$isAncestor=$true;break}
            $ancestor=$ancestor.ParentNode
        }
        if($isAncestor){continue}
        $o=Get-ProxyBounds $other.GetAttribute('bounds') -AllowEmpty
        # Flutter also exposes collapsed/off-screen controls with zero area.
        # They occupy no hit region; the actual target still requires area.
        if($o.Left -eq $o.Right -or $o.Top -eq $o.Bottom){continue}
        # A native MenuItem belongs above its single labelled popup-dismiss
        # backdrop. With a floating player Flutter may expose that backdrop as
        # a sibling instead of an ancestor. Recognize only this observed role
        # pairing; arbitrary full-screen clickables remain blockers.
        if($Node.Node.GetAttribute('class') -ceq 'android.view.MenuItem' -and
            $Node.Node.GetAttribute('package') -ceq $script:ProxyContext.Package -and
            $other.GetAttribute('class') -ceq 'android.view.View' -and
            $other.GetAttribute('package') -ceq $script:ProxyContext.Package -and
            $other.GetAttribute('content-desc') -ceq '关闭菜单' -and
            $Node.Node.OwnerDocument.SelectNodes('//node[@content-desc="关闭菜单" and @enabled="true" and @clickable="true"]').Count -eq 1 -and
            $o.Left -le $b.Left -and $o.Top -le $b.Top -and $o.Right -ge $b.Right -and $o.Bottom -ge $b.Bottom){
            continue
        }
        $o=@{Left=$o.Left-$margin;Top=$o.Top-$margin;Right=$o.Right+$margin;Bottom=$o.Bottom+$margin}
        $intersected=$false
        $regions=@(foreach($r in $regions){
            $left=[math]::Max($r.Left,$o.Left);$right=[math]::Min($r.Right,$o.Right)
            $top=[math]::Max($r.Top,$o.Top);$bottom=[math]::Min($r.Bottom,$o.Bottom)
            if($left -ge $right -or $top -ge $bottom){$r;continue}
            $intersected=$true
            @(
                @{Left=$r.Left;Top=$r.Top;Right=$left;Bottom=$r.Bottom}
                @{Left=$right;Top=$r.Top;Right=$r.Right;Bottom=$r.Bottom}
                @{Left=$left;Top=$r.Top;Right=$right;Bottom=$top}
                @{Left=$left;Top=$bottom;Right=$right;Bottom=$r.Bottom}
            ) | Where-Object {$_.Right-$_.Left -ge 16 -and $_.Bottom-$_.Top -ge 16}
        })
        if($intersected){$excluded++}
        if($regions.Count -eq 0){throw 'Proxy control is fully occluded; no input issued.'}
        if($regions.Count -gt 256){throw 'Proxy control occlusion geometry is too complex.'}
    }
    $x=[math]::Floor(($b.Left+$b.Right)/2);$y=[math]::Floor(($b.Top+$b.Bottom)/2)
    $centerFree=@($regions | Where-Object {$x -ge $_.Left -and $x -lt $_.Right -and $y -ge $_.Top -and $y -lt $_.Bottom}).Count -gt 0
    if(-not $centerFree){
        $r=$regions | Sort-Object @{Expression={($_.Right-$_.Left)*($_.Bottom-$_.Top)};Descending=$true},Top,Left | Select-Object -First 1
        $x=[math]::Floor(($r.Left+$r.Right)/2);$y=[math]::Floor(($r.Top+$r.Bottom)/2)
    }
    [pscustomobject]@{X=$x;Y=$y;ExcludedRectangles=$excluded;CenterRetained=$centerFree}
}

function Invoke-ProxyTap {
    param($Node)
    $point=Get-ProxyTapPoint $Node
    $script:ProxyContext.ActionSequence++
    $path=Join-Path $script:ProxyContext.Evidence ('proxy-tap-'+$script:ProxyContext.ActionSequence+'.json')
    [ordered]@{documentSequence=$script:ProxyContext.Sequence;bounds=$Node.Bounds;point=$point;status='planned'} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding utf8
    Invoke-ProxyAdb @('shell','input','tap',$point.X,$point.Y) | Out-Null
}

function Invoke-ProxyScroll {
    param([xml]$Document,[switch]$TowardStart)
    $areas=@($Document.SelectNodes('//node') | Where-Object {
        $_.GetAttribute('scrollable') -eq 'true' -and $_.GetAttribute('enabled') -eq 'true'
    } | ForEach-Object {
        $b=Get-ProxyBounds $_.GetAttribute('bounds')
        if ($b.Bottom-$b.Top -ge 160 -and $b.Right-$b.Left -ge 160) {
            [pscustomobject]@{Node=$_;Bounds=$b}
        }
    })
    # Flutter's floating-player wrapper can expose an outer scrollable View
    # around the actual settings ScrollView. Accept only one nested chain,
    # never guess between sibling scroll targets or outside ancestor bounds.
    $leaves=@($areas | Where-Object {
        $candidate=$_
        @($areas | Where-Object {
            $ancestor=$_.Node.ParentNode
            while ($null -ne $ancestor) {
                if ([object]::ReferenceEquals($ancestor,$candidate.Node)) { return $true }
                $ancestor=$ancestor.ParentNode
            }
            return $false
        }).Count -eq 0
    })
    if ($leaves.Count -ne 1) { throw 'Proxy scroll container is missing or ambiguous.' }
    $b=$leaves[0].Bounds
    foreach ($area in $areas) {
        $outer=$area.Bounds
        if ($outer.Left -gt $b.Left -or $outer.Top -gt $b.Top -or
            $outer.Right -lt $b.Right -or $outer.Bottom -lt $b.Bottom) {
            throw 'Proxy scroll container has inconsistent nested bounds.'
        }
    }
    $x=[math]::Floor(($b.Left+$b.Right)/2)
    $y1=[math]::Floor($b.Top+($b.Bottom-$b.Top)*0.8); $y2=[math]::Floor($b.Top+($b.Bottom-$b.Top)*0.25)
    if ($TowardStart) { $swap=$y1; $y1=$y2; $y2=$swap }
    Invoke-ProxyAdb @('shell','input','swipe',$x,$y1,$x,$y2,'280') | Out-Null
}

function Find-ProxyVisibleNode {
    param([string]$Title,[switch]$Switch,[int]$Attempts=12)
    $towardStart=$true; $previous=''
    for($i=0;$i -lt $Attempts;$i++) {
        $document=Get-ProxyUiDocument
        $node=Find-ProxyNode $document $Title -Switch:$Switch
        if ($null -ne $node) { return $node }
        $signature=$document.OuterXml
        if ($signature -ceq $previous) {
            if (-not $towardStart) { break }
            $towardStart=$false; $previous=''
        }
        if ($i -eq $Attempts-1) { break }
        Invoke-ProxyScroll $document -TowardStart:$towardStart
        $previous=$signature
    }
    throw "Proxy UI item not found within observed scrolling: $Title"
}

function Open-ProxySettings {
    # Caller either already has the proxy page or starts from the app's home.
    # Each navigation action consumes a fresh document, never a saved coordinate.
    $document=Get-ProxyUiDocument
    if ($null -ne (Find-ProxyNode $document '启用应用层代理' -Switch) -or
        $null -ne (Find-ProxyNode $document '启用播放代理' -Switch)) { return }
    $menu=Find-ProxyNode $document '菜单'
    if ($null -ne $menu) {
        Invoke-ProxyTap $menu
        $settings=Find-ProxyVisibleNode '设置' -Attempts 1
        Invoke-ProxyTap $settings
    }
    $network=Find-ProxyVisibleNode '自定义网络代理'
    Invoke-ProxyTap $network
    # A successful input command is not proof that the intended route opened.
    # Observe a bounded transition, without replaying the tap or scrolling the
    # previous settings page while looking for proxy-page switches.
    for($i=0;$i -lt 3;$i++){
        $document=Get-ProxyUiDocument
        if($null -ne (Find-ProxyNode $document '启用应用层代理' -Switch)){return}
    }
    throw 'Proxy page did not open after its single navigation tap.'
}

function Set-ProxySwitch {
    param([string]$Title,[bool]$Enabled)
    $node=Find-ProxyVisibleNode $Title -Switch
    if ($node.Checked -ne $Enabled) { Invoke-ProxyTap $node }
    # Observe even when already in the desired state; unknown is not false.
    $verified=Find-ProxyVisibleNode $Title -Switch
    if ($verified.Checked -ne $Enabled) { throw "Proxy switch did not commit: $Title" }
}

function Assert-ProxyEndpoint {
    param([string]$Title,[int]$Port)
    Find-ProxyVisibleNode $Title -Switch | Out-Null
    $document=Get-ProxyUiDocument
    Assert-ProxyEndpointDocument $document $Title $Port
}

function Assert-ProxyEndpointDocument {
    param([xml]$Document,[string]$Title,[int]$Port)
    $switch=Find-ProxyNode $Document $Title -Switch
    if ($null -eq $switch -or -not $switch.Checked) { throw 'Enabled proxy switch is not visible.' }
    $otherTitle=if($Title -ceq '启用应用层代理'){'启用播放代理'}else{'启用应用层代理'}
    $other=Find-ProxyNode $Document $otherTitle -Switch
    $limit=if($null -ne $other -and $other.Bounds.Top -gt $switch.Bounds.Top){$other.Bounds.Top}else{[int]::MaxValue}
    $fields=@($Document.SelectNodes('//node') | Where-Object { $_.GetAttribute('class') -eq 'android.widget.EditText' } | ForEach-Object {
        $b=Get-ProxyBounds $_.GetAttribute('bounds')
        if($b.Top -ge $switch.Bounds.Bottom -and $b.Bottom -le $limit){
            [pscustomobject]@{Left=$b.Left;Top=$b.Top;Value=$_.GetAttribute('text')}
        }
    } | Sort-Object Top,Left)
    if($fields.Count -ne 2 -or $fields[0].Value -cne '127.0.0.1' -or $fields[1].Value -cne [string]$Port){
        throw "The $Title endpoint fields are not verified as 127.0.0.1:$Port."
    }
}

function Get-ProxyReverseBinding {
    param([int]$Port)
    $lines=@(Invoke-ProxyAdb @('reverse','--list'))
    $matches=@(foreach($line in $lines){
        if([string]::IsNullOrWhiteSpace($line)){continue}
        if($line -notmatch '^\S+\s+(\S+)\s+(\S+)\s*$'){throw 'Unexpected reverse-list format.'}
        if($Matches[1] -ceq "tcp:$Port"){$Matches[2]}
    })
    if($matches.Count -gt 1){throw 'Ambiguous reverse mapping.'}
    if($matches.Count -eq 1){return [string]$matches[0]}
    ''
}

function Save-ProxySession {
    param([Collections.IDictionary]$Session,[string]$Path)
    $temporary=$Path+'.tmp'
    $Session.updatedAt=[DateTime]::UtcNow.ToString('o')
    $Session | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temporary -Encoding utf8
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Read-ProxySession {
    param([string]$Path,[string]$Serial)
    # ConvertFrom-Json -AsHashtable starts in PowerShell 6. Build the flat
    # session dictionary explicitly so the same recovery journal works in the
    # Windows PowerShell 5.1 shell used by local/device operators.
    $decoded=Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json
    $s=[ordered]@{}
    foreach($property in @($decoded.PSObject.Properties)){$s[$property.Name]=$property.Value}
    if($s['schemaVersion'] -ne 1 -or $s['serial'] -cne $Serial -or $s['package'] -cne 'com.mystyle.purelive' -or
        $s['model'] -cne '25102RKBEC' -or $s['device'] -cne 'myron' -or
        ($s['port'] -isnot [long] -and $s['port'] -isnot [int])){throw 'Proxy session identity/schema mismatch.'}
    if($s['port'] -lt 1 -or $s['port'] -gt 65535){throw 'Invalid proxy session port.'}
    foreach($key in @('ownedReverse','reverseUncertain','uiMayHaveChanged','previousApp','previousPlayer')){
        if($s[$key] -isnot [bool]){throw "Invalid proxy session flag: $key"}
    }
    $s
}

function Acquire-ProxyReverse {
    param([Collections.IDictionary]$Session,[string]$Path)
    $binding=Get-ProxyReverseBinding $Session.port
    if($binding -and $binding -cne "tcp:$($Session.port)"){throw 'Requested reverse port belongs to another mapping.'}
    if(-not $binding){
        $Session.status='reverse-create-pending'; $Session.reverseUncertain=$true; Save-ProxySession $Session $Path
        Invoke-ProxyAdb @('reverse','--no-rebind',"tcp:$($Session.port)","tcp:$($Session.port)") | Out-Null
        $Session.ownedReverse=$true
        $Session.reverseUncertain=$false
        Save-ProxySession $Session $Path
    }
    if((Get-ProxyReverseBinding $Session.port) -cne "tcp:$($Session.port)"){throw 'Reverse mapping verification failed.'}
    $Session.status='reverse-ready'; Save-ProxySession $Session $Path
}

function Remove-OwnedProxyReverse {
    param([Collections.IDictionary]$Session,[string]$Path)
    if($Session.reverseUncertain){
        if(Get-ProxyReverseBinding $Session.port){throw 'Reverse creation outcome is uncertain; preserving the observed mapping.'}
        $Session.reverseUncertain=$false; Save-ProxySession $Session $Path
    }
    if(-not $Session.ownedReverse){return}
    $binding=Get-ProxyReverseBinding $Session.port
    if($binding -and $binding -cne "tcp:$($Session.port)"){
        # Observing replacement permanently relinquishes ownership. A later
        # identical destination must not revive this old journal's delete right.
        $Session.ownedReverse=$false; Save-ProxySession $Session $Path
        throw 'Owned reverse mapping was replaced; preserving its new destination.'
    }
    if($binding){Invoke-ProxyAdb @('reverse','--remove',"tcp:$($Session.port)") | Out-Null}
    if(Get-ProxyReverseBinding $Session.port){throw 'Reverse mapping remains after cleanup.'}
    $Session.ownedReverse=$false; Save-ProxySession $Session $Path
}

function Restore-ProxySession {
    param([Collections.IDictionary]$Session,[string]$Path,[switch]$AllowHomeLaunch)
    # Removing our own transport never requires seizing the foreground.
    try {
        Remove-OwnedProxyReverse $Session $Path
        if($Session.uiMayHaveChanged){
            if($AllowHomeLaunch){
                $homeReply=(Invoke-ProxyAdb @('shell','cmd','package','resolve-activity','--brief','-a','android.intent.action.MAIN','-c','android.intent.category.HOME')) -join "`n"
                if($homeReply -match '(?m)^(?<pkg>[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+)/[^\s]+\s*$'){$script:ProxyContext.HomePackage=$Matches['pkg']}
                Assert-ProxyForeground -AllowHome
                # am start is scoped to a valid cleanup journal and target/HOME.
                Invoke-ProxyAdb @('shell','am','start','-W','-n','com.mystyle.purelive/.MainActivity') -AllowHome | Out-Null
            }else{Assert-ProxyForeground}
            Open-ProxySettings
            Set-ProxySwitch '启用播放代理' $Session.previousPlayer
            Set-ProxySwitch '启用应用层代理' $Session.previousApp
            $Session.uiMayHaveChanged=$false
        }
        $Session.status='restored'; Save-ProxySession $Session $Path
    }catch{
        $Session.status='cleanup-pending'; Save-ProxySession $Session $Path
        throw
    }
}

function Start-ProxySession {
    param([int]$Port,[string]$Path)
    if(Test-Path -LiteralPath $Path){throw 'Proxy session path already exists; restore it or choose a fresh session.'}
    Assert-ProxyForeground
    # Check conflicts before navigating or touching switches.
    $binding=Get-ProxyReverseBinding $Port
    if($binding -and $binding -cne "tcp:$Port"){throw 'Requested reverse port belongs to another mapping.'}
    Open-ProxySettings
    $app=Find-ProxyVisibleNode '启用应用层代理' -Switch
    $player=Find-ProxyVisibleNode '启用播放代理' -Switch
    $session=[ordered]@{
        schemaVersion=1;serial=$script:ProxyContext.Serial;package=$script:ProxyContext.Package
        model='25102RKBEC';device='myron';port=$Port;ownedReverse=$false;reverseUncertain=$false
        previousApp=[bool]$app.Checked;previousPlayer=[bool]$player.Checked
        uiMayHaveChanged=$false;status='prepared';updatedAt=''
    }
    Save-ProxySession $session $Path
    try{
        Acquire-ProxyReverse $session $Path
        $session.uiMayHaveChanged=$true; Save-ProxySession $session $Path
        Set-ProxySwitch '启用应用层代理' $true
        Assert-ProxyEndpoint '启用应用层代理' $Port
        Set-ProxySwitch '启用播放代理' $true
        Assert-ProxyEndpoint '启用播放代理' $Port
        $session.status='enabled'; Save-ProxySession $session $Path
    }catch{
        $failure=$_
        try{Restore-ProxySession $session $Path}catch{Write-Warning "Proxy cleanup is pending: $Path"}
        throw $failure
    }
    $Path
}
