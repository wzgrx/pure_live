$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot 'android_recording_smoke.ps1'
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$platformParameter = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Platform' }
$attribute = $platformParameter.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' }
$accepted = @($attribute.PositionalArguments | ForEach-Object Value)
function Find-Assignment([string]$Name) {
 $ast.Find({param($node)
  $node -is [Management.Automation.Language.AssignmentStatementAst] -and
  $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and
  $node.Left.VariablePath.UserPath -eq $Name
 }, $true)
}
$labelAssignment = Find-Assignment 'platformLabels'
$table = $labelAssignment.Right.Find({param($n) $n -is [Management.Automation.Language.HashtableAst]}, $true).SafeGetValue()
$capability = (Find-Assignment 'danmakuSupported').Right.Extent.Text
$expected = @('bilibili','douyu','huya','douyin','kuaishou','cc','twitch','soop','yy','acfun')
if (@(Compare-Object ($accepted | Sort-Object) ($expected | Sort-Object)).Count) { throw 'Accepted platform set differs from the recording matrix' }
if (@(Compare-Object (@($table.Keys) | Sort-Object) ($expected | Sort-Object)).Count) { throw 'Platform labels and accepted input differ' }
foreach ($Platform in $expected) {
 $supported = & ([scriptblock]::Create($capability))
 if ($supported -ne ($Platform -notin @('cc','acfun'))) { throw "Incorrect remote chat capability for $Platform" }
 if ([string]::IsNullOrWhiteSpace($table[$Platform])) { throw "Missing platform label for $Platform" }
 Write-Host "PASS $Platform label/chat contract"
}
$translations = Get-Content (Join-Path $PSScriptRoot '../assets/translations/zh.json') -Raw -Encoding utf8 | ConvertFrom-Json
if ($table['acfun'] -ne $translations.site_acfun) { throw 'AcFun navigation label differs from the actual translation' }
Write-Host 'PASS AcFun localized label'
