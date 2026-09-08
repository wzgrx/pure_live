[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string] $OfficialCodecPath,
 [Parameter(Mandatory=$true)][string] $OutputPath
)
# Independent .NET fixtures for the reviewed public website codec.
$ErrorActionPreference='Stop'
$source=$OfficialCodecPath
$js=Get-Content $source -Raw -Encoding utf8
if((Get-FileHash $source).Hash-ne'2A031560D9CCD3770FF57969B8818E5EAFD6D8A1E4F54C87E0F4BD983D4607E2'){throw 'Review source changed'}
$new=[regex]::Match($js,'newSecretKey,i=void 0===o\?"([^"]+)"').Groups[1].Value
$old=[regex]::Match($js,'t.secretKey,n=void 0===r\?"([^"]+)"').Groups[1].Value
$iv=[regex]::Match($js,'t.iv,u=void 0===c\?"([^"]+)"').Groups[1].Value
$salt=[regex]::Match($js,'B="([^"]+)",O="uxin-security-url-crypto"').Groups[1].Value
$cases=[Collections.Generic.List[object]]::new()
function Hash([string]$value){$h=[Security.Cryptography.MD5]::Create();try{return [Convert]::ToHexString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($value))).ToLowerInvariant()}finally{$h.Dispose()}}
function Enc([string]$plain,[string]$key){$a=[Security.Cryptography.Aes]::Create();try{$a.Key=[Text.Encoding]::UTF8.GetBytes($key);$a.IV=[Text.Encoding]::UTF8.GetBytes($iv);$a.Mode='CBC';$a.Padding='PKCS7';$e=$a.CreateEncryptor();try{$b=[Text.Encoding]::UTF8.GetBytes($plain);return [Convert]::ToBase64String($e.TransformFinalBlock($b,0,$b.Length)).Replace('+','-').Replace('/','_')}finally{$e.Dispose()}}finally{$a.Dispose()}}
foreach($keyName in @('new','old')) {
 $key=if($keyName-eq'new'){$new}else{$old}
 foreach($hostName in @('live.kilakila.cn','www.hongdoufm.com')){
  foreach($style in @('detail','room')){
   $id='9007199254740993123';$prefix=if($style-eq'detail'){"https://$hostName/PcLive/index/detail?"}else{"https://$hostName/room/"}
   $signed=if($style-eq'detail'){'id='+$id}else{$id};$sign=Hash ($salt+$prefix+$signed)
   $plain=if($style-eq'detail'){$signed+'&sign='+$sign}else{$id+'?sign='+$sign}
   $payload=Enc $plain $key;$url=$prefix+$(if($style-eq'detail'){'_specific_parameter='}else{''})+[Uri]::EscapeDataString($payload)
   $cases.Add([ordered]@{name="$keyName-$hostName-$style";url=$url;kind='broadcast';id=$id;valid=$true})
   $cases.Add([ordered]@{name="$keyName-$hostName-$style-wrong-signature";url=$url.Replace($hostName,$(if($hostName-eq'live.kilakila.cn'){'www.hongdoufm.com'}else{'live.kilakila.cn'}));valid=$false})
  }
 }
 $id='1234567890123';$prefix='https://live.hongrenshuo.com.cn/index/roomuser/uid/';$sign=Hash ($salt+$prefix+$id)
 $cases.Add([ordered]@{name="$keyName-owner";url=$prefix+[Uri]::EscapeDataString((Enc ($id+'?sign='+$sign) $key));kind='owner';id=$id;valid=$true})
}
$id='12345';$prefix='https://live.kilakila.cn/room/';$sign=Hash ($salt+$prefix+$id+'?from=hello world&tag=one+two')
$cases.Add([ordered]@{name='room-extra-decoded-parameters';url=$prefix+[Uri]::EscapeDataString((Enc ($id+'?tag=one%2Btwo&from=hello+world&sign='+$sign) $new));kind='broadcast';id=$id;valid=$true})
$prefix='https://live.kilakila.cn/PcLive/index/detail?';$params='from=hello%20world&id='+$id;$sign=Hash ($salt+$prefix+$params)
$cases.Add([ordered]@{name='detail-extra-raw-parameters';url=$prefix+'_specific_parameter='+[Uri]::EscapeDataString((Enc ('id='+$id+'&from=hello%20world&sign='+$sign) $new));kind='broadcast';id=$id;valid=$true})
foreach($plain in @('id=123&id=456&sign=00000000000000000000000000000000','123?id=456&sign=00000000000000000000000000000000','id=123&sign=00000000000000000000000000000000','id=123&sign=bad','id=0&sign=00000000000000000000000000000000','id=123&bad','id=123&extra=a=b&sign=00000000000000000000000000000000')){
 $cases.Add([ordered]@{name="malformed-plaintext-$($cases.Count)";url=$prefix+'_specific_parameter='+[Uri]::EscapeDataString((Enc $plain $new));valid=$false})
}
$cases.Add([ordered]@{name='observed-official-desktop-share';url='https://live.kilakila.cn/PcLive/index/detail?_specific_parameter=8abW5b6lAuaTkYSdFeYAUtCDjvcjEMyYUOF_GYBfX2MYKbDRiHkHa6BlOp5GiieeEoOW0qtHDspcP2AedMXnfw%3D%3D';kind='broadcast';id='2261269383617708096';valid=$true})
$out=$OutputPath
New-Item -ItemType Directory -Force (Split-Path $out -Parent) | Out-Null
$cases.ToArray() | ConvertTo-Json -Depth 5 | Set-Content $out -Encoding utf8
Write-Output "Generated $($cases.Count) independent fixtures."

