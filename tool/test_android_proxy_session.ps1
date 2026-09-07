[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'android_recording_navigation.ps1')
. (Join-Path $PSScriptRoot 'android_proxy_session.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('purelive-proxy-test-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$script:passed=0
function Equal($a,$b,[string]$message){if($a -cne $b){throw "$message : expected '$b', got '$a'"}}
function Throws([scriptblock]$body,[string]$pattern){
    $message='';try{& $body | Out-Null}catch{$message=$_.Exception.Message}
    if($message -notmatch $pattern){throw "Expected '$pattern', got '$message'"}
}
function Node([string]$title,[int]$y,[bool]$checked=$false,[switch]$Switch){
    $check=if($Switch){'checkable="true" checked="'+$checked.ToString().ToLowerInvariant()+'"'}else{'checkable="false"'}
    '<node text="{0}" content-desc="" enabled="true" clickable="true" {1} bounds="[100,{2}][500,{3}]"/>' -f $title,$check,$y,($y+80)
}
function Fake-Document {
    $body=switch($script:fake.Page){
        'home' {Node '菜单' 100}
        'drawer' {Node '设置' 200}
        'settings' {Node '自定义网络代理' 300}
        'proxy' {
            $playerY=if($script:fake.App){440}else{240}
            $parts=@((Node '启用应用层代理' 100 $script:fake.App -Switch),(Node '启用播放代理' $playerY $script:fake.Player -Switch))
            foreach($pair in @(@($script:fake.App,200),@($script:fake.Player,($playerY+100)))){
                if($pair[0]){
                    $hostValue=if($script:fake.BadEndpoint){''}else{'127.0.0.1'}
                    $parts+='<node class="android.widget.EditText" text="'+$hostValue+'" content-desc="127.0.0.1" enabled="true" bounds="[100,'+$pair[1]+'][300,'+($pair[1]+80)+']"/>'
                    $parts+='<node class="android.widget.EditText" text="'+$script:fake.Port+'" enabled="true" bounds="[320,'+$pair[1]+'][500,'+($pair[1]+80)+']"/>'
                }
            }
            $parts -join ''
        }
    }
    '<hierarchy><node enabled="true" scrollable="true" bounds="[0,0][1200,1600]">'+$body+'</node></hierarchy>'
}
function Reset-Fake {
    $script:fake=@{Model='25102RKBEC';Device='myron';Foreground='com.mystyle.purelive';Page='home';App=$false;Player=$false;Port=7909
        Reverse='';CreateError=$false;CreateAmbiguous=$false;FailInput=$false;LoseAfterApp=$false;BadEndpoint=$false;Dump=''}
    $script:calls=[Collections.Generic.List[string]]::new()
    $script:FakeAdb={
        param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
        if($Arguments[0] -cne '-s' -or $Arguments[1] -cne '192.0.2.10:5555'){throw 'Unbound/wrong fixture target'}
        $a=@($Arguments | Select-Object -Skip 2); $cmd=$a -join ' '; $script:calls.Add($cmd); $global:LASTEXITCODE=0
        switch -Regex ($cmd){
            '^shell getprop ro.product.model$' {$script:fake.Model;break}
            '^shell getprop ro.product.device$' {$script:fake.Device;break}
            '^shell dumpsys activity activities$' {'topResumedActivity=ActivityRecord{1 u0 '+$script:fake.Foreground+'/.Activity t1}';break}
            '^shell cmd package resolve-activity' {'example.launcher/.Home';break}
            '^shell am start ' {$script:fake.Foreground='com.mystyle.purelive';$script:fake.Page='home';break}
            '^reverse --list$' {if($script:fake.Reverse){'UsbFfs tcp:'+$script:fake.Port+' '+$script:fake.Reverse};break}
            '^reverse --no-rebind ' {
                if($script:fake.CreateAmbiguous){$script:fake.Reverse='tcp:'+$script:fake.Port;$global:LASTEXITCODE=1;'transport closed'}
                elseif($script:fake.CreateError){$global:LASTEXITCODE=1;'bind failed'}
                elseif($script:fake.Reverse){throw 'Fixture forbids rebinding an existing reverse'}
                else{$script:fake.Reverse='tcp:'+$script:fake.Port}
                break
            }
            '^reverse --remove ' {Equal $a[2] ('tcp:'+$script:fake.Port) 'cleanup port';$script:fake.Reverse='';break}
            '^shell uiautomator dump ' {$script:fake.Dump=Fake-Document;'UI hierarchy dumped';break}
            '^pull ' {$script:fake.Dump | Set-Content -LiteralPath $a[2] -Encoding utf8;break}
            '^shell rm -f ' {break}
            '^shell input tap ' {
                if($script:fake.FailInput){$global:LASTEXITCODE=1;'device offline';break}
                $y=[int]$a[4]
                switch($script:fake.Page){
                    'home' {Equal $y 140 'home semantic';$script:fake.Page='drawer'}
                    'drawer' {Equal $y 240 'drawer semantic';$script:fake.Page='settings'}
                    'settings' {Equal $y 340 'settings semantic';$script:fake.Page='proxy'}
                    'proxy' {
                        if($y -eq 140){$script:fake.App=-not $script:fake.App;if($script:fake.LoseAfterApp){$script:fake.Foreground='example.other'}}
                        else{$expected=if($script:fake.App){480}else{280};Equal $y $expected 'fresh player switch location';$script:fake.Player=-not $script:fake.Player}
                    }
                }
                break
            }
            '^shell input swipe ' {break}
            default {throw "Unexpected fixture command: $cmd"}
        }
    }
    $script:sessionPath=Join-Path $root ([Guid]::NewGuid().ToString('N')+'.json')
    Initialize-ProxyContext -Serial '192.0.2.10:5555' -AdbExecutable $script:FakeAdb -EvidenceDirectory $root
}
function Case([string]$Name,[scriptblock]$Body){Reset-Fake;& $Body;$script:passed++;Write-Output "PASS $Name"}
try{
    Case 'owned custom port setup and restore with fresh switch bounds' {
        Start-ProxySession 7909 $sessionPath | Out-Null
        $s=Read-ProxySession $sessionPath '192.0.2.10:5555'
        Equal $s.status 'enabled' 'setup';Equal $s.ownedReverse $true 'owns new binding'
        Equal $fake.App $true 'app enabled';Equal $fake.Player $true 'player enabled'
        Restore-ProxySession $s $sessionPath
        Equal $fake.Reverse '' 'owned binding removed';Equal $fake.App $false 'app restored';Equal $fake.Player $false 'player restored'
        Equal $s.status 'restored' 'journal restored'
        $before=$calls.Count;Restore-ProxySession $s $sessionPath;Equal $calls.Count $before 'idempotent restore has no ADB'
    }
    Case 'borrowed identical reverse is never rebound or removed' {
        $fake.Reverse='tcp:7909';Start-ProxySession 7909 $sessionPath | Out-Null
        $s=Read-ProxySession $sessionPath '192.0.2.10:5555';Equal $s.ownedReverse $false 'borrowed'
        Restore-ProxySession $s $sessionPath
        Equal $fake.Reverse 'tcp:7909' 'existing reverse preserved'
        Equal @($calls|Where-Object {$_ -match '^reverse --no-rebind|^reverse --remove'}).Count 0 'no reverse mutation'
    }
    Case 'conflicting reverse fails before navigation or journal' {
        $fake.Reverse='tcp:9999';Throws {Start-ProxySession 7909 $sessionPath} 'belongs to another'
        Equal $fake.Reverse 'tcp:9999' 'conflict preserved';Equal (Test-Path $sessionPath) $false 'no session'
        Equal @($calls|Where-Object {$_ -match 'shell input'}).Count 0 'no input'
    }
    Case 'other app blocks setup before mapping mutation' {
        $fake.Foreground='example.other';Throws {Start-ProxySession 7909 $sessionPath} 'foreground changed'
        Equal $fake.Reverse '' 'no mapping';Equal (Test-Path $sessionPath) $false 'no journal'
        Equal @($calls|Where-Object {$_ -match 'shell input|shell am start'}).Count 0 'no takeover'
    }
    Case 'empty host with loopback hint fails and rolls back' {
        $fake.BadEndpoint=$true;Throws {Start-ProxySession 7909 $sessionPath} 'endpoint fields'
        $s=Read-ProxySession $sessionPath '192.0.2.10:5555'
        Equal $s.status 'restored' 'failed setup rolled back';Equal $fake.App $false 'app off';Equal $fake.Reverse '' 'reverse removed'
    }
    Case 'foreground loss clears owned routing but records pending UI cleanup' {
        $fake.LoseAfterApp=$true;Throws {Start-ProxySession 7909 $sessionPath} 'foreground changed'
        $s=Read-ProxySession $sessionPath '192.0.2.10:5555'
        Equal $s.status 'cleanup-pending' 'cleanup pending';Equal $s.uiMayHaveChanged $true 'UI not claimed restored'
        Equal $fake.Reverse '' 'owned route removed';Equal $fake.App $true 'no blind toggle after loss'
        Equal @($calls|Where-Object {$_ -match 'shell am start'}).Count 0 'no foreground recovery'
        $fake.LoseAfterApp=$false;$fake.Foreground='com.mystyle.purelive'
        Initialize-ProxyContext '192.0.2.10:5555' $FakeAdb $root
        Restore-ProxySession $s $sessionPath
        Equal $s.status 'restored' 'later verified cleanup';Equal $fake.App $false 'original app state'
    }
    Case 'cleanup from another app never launches target' {
        Start-ProxySession 7909 $sessionPath|Out-Null;$s=Read-ProxySession $sessionPath '192.0.2.10:5555'
        $fake.Foreground='example.other'
        Throws {Restore-ProxySession $s $sessionPath -AllowHomeLaunch} 'foreground changed'
        Equal $fake.Reverse '' 'owned reverse removed first';Equal @($calls|Where-Object {$_ -match 'shell am start'}).Count 0 'no launch'
    }
    Case 'journal cleanup may reenter from the resolved launcher' {
        Start-ProxySession 7909 $sessionPath|Out-Null;$s=Read-ProxySession $sessionPath '192.0.2.10:5555'
        $fake.Foreground='example.launcher';Restore-ProxySession $s $sessionPath -AllowHomeLaunch
        Equal $s.status 'restored' 'launcher cleanup';Equal @($calls|Where-Object {$_ -match 'shell am start'}).Count 1 'one scoped reentry'
    }
    Case 'replaced mapping is preserved and cleanup remains pending' {
        Start-ProxySession 7909 $sessionPath|Out-Null;$s=Read-ProxySession $sessionPath '192.0.2.10:5555';$fake.Reverse='tcp:9999'
        Throws {Restore-ProxySession $s $sessionPath} 'replaced';Equal $fake.Reverse 'tcp:9999' 'new owner preserved'
        Equal $s.status 'cleanup-pending' 'not a successful cleanup'
        Equal $s.ownedReverse $false 'known replacement permanently ends ownership'
        $fake.Reverse='tcp:7909';Restore-ProxySession $s $sessionPath
        Equal $fake.Reverse 'tcp:7909' 'return to an identical destination does not revive ownership'
    }
    Case 'uncertain reverse creation is not adopted or removed' {
        $fake.CreateAmbiguous=$true;Throws {Start-ProxySession 7909 $sessionPath} 'command failed'
        $s=Read-ProxySession $sessionPath '192.0.2.10:5555'
        Equal $s.reverseUncertain $true 'uncertain';Equal $s.status 'cleanup-pending' 'pending'
        Equal $fake.Reverse 'tcp:7909' 'uncertain mapping preserved';Equal $fake.App $false 'no switch changes'
    }
    Case 'definite creation failure with no mapping rolls back without deletion' {
        $fake.CreateError=$true;Throws {Start-ProxySession 7909 $sessionPath} 'command failed'
        $s=Read-ProxySession $sessionPath '192.0.2.10:5555';Equal $s.status 'restored' 'no residue'
        Equal @($calls|Where-Object {$_ -match '^reverse --remove'}).Count 0 'no unrelated removal'
    }
    Case 'pre-existing mixed switches are restored individually' {
        $fake.App=$true;$fake.Page='proxy';Start-ProxySession 7909 $sessionPath|Out-Null
        $s=Read-ProxySession $sessionPath '192.0.2.10:5555';Restore-ProxySession $s $sessionPath
        Equal $fake.App $true 'original app on';Equal $fake.Player $false 'original player off'
    }
    Case 'mismatched session serial stops before any command' {
        Start-ProxySession 7909 $sessionPath|Out-Null;$before=$calls.Count
        Throws {Read-ProxySession $sessionPath '192.0.2.11:5555'} 'identity/schema'
        Equal $calls.Count $before 'no retarget'
    }
    Case 'reuse of a session path does not change the device' {
        Start-ProxySession 7909 $sessionPath|Out-Null;$before=$calls.Count
        Throws {Start-ProxySession 7909 $sessionPath} 'already exists';Equal $calls.Count $before 'no overwritten journal'
    }
    Case 'failed input has one attempt and no UI cleanup replay' {
        $fake.Page='proxy';$fake.FailInput=$true;Throws {Start-ProxySession 7909 $sessionPath} 'command failed'
        Equal @($calls|Where-Object {$_ -match 'shell input tap'}).Count 1 'one attempt'
        $s=Read-ProxySession $sessionPath '192.0.2.10:5555';Equal $s.status 'cleanup-pending' 'pending outcome'
        Equal $fake.Reverse '' 'owned route removed'
    }
    Case 'missing switch state and duplicate semantics are not false' {
        $doc=[xml]'<hierarchy><node text="启用应用层代理" enabled="true" clickable="true" bounds="[0,0][100,80]"/></hierarchy>'
        Equal ($null -eq (Find-ProxyNode $doc '启用应用层代理' -Switch)) $true 'missing checkable state'
        $doc=[xml]('<hierarchy>'+(Node '启用应用层代理' 100 $false -Switch)+(Node '启用应用层代理' 200 $false -Switch)+'</hierarchy>')
        Throws {Find-ProxyNode $doc '启用应用层代理' -Switch} 'Ambiguous'
    }
    Case 'model mismatch performs properties only' {
        $calls.Clear();$fake.Model='other';Throws {Initialize-ProxyContext '192.0.2.10:5555' $FakeAdb $root} 'model/device'
        Equal $calls.Count 2 'read-only identity checks'
    }
    Case 'missing serial has zero commands' {
        $calls.Clear();Throws {Initialize-ProxyContext '' $FakeAdb $root} 'explicit proxy Serial';Equal $calls.Count 0 'no discovery'
    }
    Case 'historical device XML validates both independent endpoint rows' {
        $document=[xml](Get-Content -LiteralPath (Join-Path $PSScriptRoot 'tests/fixtures/android_proxy_switches_enabled.xml') -Raw -Encoding utf8)
        Assert-ProxyEndpointDocument $document '启用应用层代理' 7897
        Assert-ProxyEndpointDocument $document '启用播放代理' 7897
        Throws {Assert-ProxyEndpointDocument $document '启用播放代理' 7909} 'endpoint fields'
        $fields=@($document.SelectNodes('//node[@class="android.widget.EditText"]'))
        $fields[2].SetAttribute('text','different.example')
        Assert-ProxyEndpointDocument $document '启用应用层代理' 7897
        Throws {Assert-ProxyEndpointDocument $document '启用播放代理' 7897} 'endpoint fields'
        Equal $calls.Count 2 'historical XML validation is pure after fixture initialization'
    }
    Case 'port schema rejects a malformed cleanup journal' {
        Start-ProxySession 7909 $sessionPath|Out-Null
        $s=Read-ProxySession $sessionPath '192.0.2.10:5555';$s.port='7897; unexpected'
        Save-ProxySession $s $sessionPath
        Throws {Read-ProxySession $sessionPath '192.0.2.10:5555'} 'identity/schema'
    }
    Write-Output "SUMMARY $script:passed proxy transaction scenarios passed; actual ADB commands: 0"
}finally{
    $absolute=[IO.Path]::GetFullPath($root)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not $absolute.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $absolute -Leaf) -notlike 'purelive-proxy-test-*'){throw 'Unexpected cleanup path'}
    Remove-Item -LiteralPath $absolute -Recurse -Force
}
