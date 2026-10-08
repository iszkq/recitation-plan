$ErrorActionPreference = 'Stop'
$recitationRoot = Split-Path -Parent $PSScriptRoot
$recitationDart = Join-Path $recitationRoot '.tools/dart-sdk/bin/dart.exe'
if (!(Test-Path -LiteralPath $recitationDart)) { throw '先运行 scripts/setup-dart.py 下载并校验 SDK。' }
$env:PUB_CACHE = Join-Path $recitationRoot '.tools/pub-cache'
Push-Location (Join-Path $recitationRoot 'product/core')
try {
  & $recitationDart --suppress-analytics pub get
  if ($LASTEXITCODE) { throw '依赖获取失败' }
  & $recitationDart --suppress-analytics analyze
  if ($LASTEXITCODE) { throw '静态分析失败' }
  & $recitationDart --suppress-analytics test
  if ($LASTEXITCODE) { throw '测试失败' }
} finally { Pop-Location }
