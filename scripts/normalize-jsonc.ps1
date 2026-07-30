param(
  [Parameter(Mandatory)][string]$Path,
  [switch]$SetDefaultAgent
)

$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL_7_REQUIRED'}

function Remove-JsoncComments([string]$Text){
  $builder=[Text.StringBuilder]::new();$index=0;$inString=$false;$escaped=$false;$lineComment=$false;$blockComment=$false
  while($index-lt$Text.Length){
    $char=$Text[$index];$next=if($index+1-lt$Text.Length){$Text[$index+1]}else{[char]0}
    if($lineComment){if($char-eq"`r"-or$char-eq"`n"){$lineComment=$false;$null=$builder.Append($char)};$index++;continue}
    if($blockComment){if($char-eq'*'-and$next-eq'/'){$blockComment=$false;$index+=2;continue};if($char-eq"`r"-or$char-eq"`n"){$null=$builder.Append($char)};$index++;continue}
    if($inString){
      $null=$builder.Append($char)
      if($escaped){$escaped=$false}elseif($char-eq'\'){$escaped=$true}elseif($char-eq'"'){$inString=$false}
      $index++;continue
    }
    if($char-eq'"'){$inString=$true;$null=$builder.Append($char);$index++;continue}
    if($char-eq'/'-and$next-eq'/'){$lineComment=$true;$index+=2;continue}
    if($char-eq'/'-and$next-eq'*'){$blockComment=$true;$index+=2;continue}
    $null=$builder.Append($char);$index++
  }
  if($inString-or$blockComment){throw 'JSONC contains an unterminated string or block comment.'}
  $builder.ToString()
}

function Remove-TrailingCommas([string]$Text){
  $builder=[Text.StringBuilder]::new();$index=0;$inString=$false;$escaped=$false
  while($index-lt$Text.Length){
    $char=$Text[$index]
    if($inString){
      $null=$builder.Append($char)
      if($escaped){$escaped=$false}elseif($char-eq'\'){$escaped=$true}elseif($char-eq'"'){$inString=$false}
      $index++;continue
    }
    if($char-eq'"'){$inString=$true;$null=$builder.Append($char);$index++;continue}
    if($char-eq','){
      $lookahead=$index+1
      while($lookahead-lt$Text.Length-and[char]::IsWhiteSpace($Text[$lookahead])){$lookahead++}
      if($lookahead-lt$Text.Length-and($Text[$lookahead]-eq'}'-or$Text[$lookahead]-eq']')){$index++;continue}
    }
    $null=$builder.Append($char);$index++
  }
  $builder.ToString()
}

if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "JSONC path not found: $Path"}
$Raw=Get-Content -LiteralPath $Path -Raw
$Clean=Remove-TrailingCommas (Remove-JsoncComments $Raw)
try{$Value=if([string]::IsNullOrWhiteSpace($Clean)){[pscustomobject][ordered]@{'$schema'='https://opencode.ai/config.json'}}else{$Clean|ConvertFrom-Json}}catch{throw "Cannot safely parse ${Path}: $($_.Exception.Message)"}
if($Value-isnot[pscustomobject]){throw "OpenCode configuration root must be an object: $Path"}
if($SetDefaultAgent){$Value|Add-Member NoteProperty default_agent 'architect' -Force}
$Normalized=($Value|ConvertTo-Json -Depth 50)+[Environment]::NewLine
[IO.File]::WriteAllText($Path,$Normalized,(New-Object Text.UTF8Encoding($false)))
