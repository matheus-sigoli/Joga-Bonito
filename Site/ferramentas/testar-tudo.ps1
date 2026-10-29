# ============================================================================
# JOGA BONITO — roda TODOS os testes no Windows e mostra um resumo
#   testar-tudo.bat                    (na raiz do projeto)
#   testar-tudo.bat -PularFlutter      (sem o app)
#
#   1. Unitários da API (xUnit)
#   2. Integração: API real + SQL Server local (banco temporário, apagado no fim)
#   3. E2E do site (Playwright + API simulada na porta 5000)
#   4. Aceitação contra a API REAL (sobe a loja com o lançador e roda validar_loja.py)
#   5. App: flutter analyze, flutter test e APK de produção
# Requisitos: .NET 8 SDK, SQL Server, Python 3.10+ (pip install playwright;
# python -m playwright install chromium) e, para o app, Flutter.
# ============================================================================
param([switch]$PularFlutter, [string]$UrlApk = '')

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$Raiz = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Lancador = Join-Path $PSScriptRoot 'jogabonito.ps1'
$Logs = Join-Path $env:LOCALAPPDATA 'JogaBonito\logs'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
$resultado = [ordered]@{}

function Etapa([string]$nome, [scriptblock]$acao) {
    Write-Host ''
    Write-Host "== $nome" -ForegroundColor Cyan
    $log = Join-Path $Logs ("teste-" + ($nome -replace '[^A-Za-z0-9]+', '-').ToLower() + '.log')
    $inicio = Get-Date
    try {
        & $acao *>&1 | Tee-Object -FilePath $log | Select-Object -Last 15 | ForEach-Object { Write-Host "   $_" }
        $ok = ($LASTEXITCODE -eq 0)
    } catch {
        Write-Host "   $($_.Exception.Message)" -ForegroundColor Red
        $ok = $false
    }
    $tempo = [int]((Get-Date) - $inicio).TotalSeconds
    $resultado[$nome] = @{ Ok = $ok; Tempo = $tempo; Log = $log }
    if ($ok) { Write-Host "   [ok] $nome (${tempo}s)" -ForegroundColor Green }
    else { Write-Host "   [FALHOU] $nome - log completo: $log" -ForegroundColor Red }
}

function Pular([string]$nome, [string]$motivo) {
    $resultado[$nome] = @{ Ok = $null; Motivo = $motivo }
    Write-Host ''
    Write-Host "== $nome" -ForegroundColor Cyan
    Write-Host "   [pulado] $motivo" -ForegroundColor Yellow
}

Set-Location $Raiz

# 1 ------------------------------------------------------------- unitários
Etapa 'Unitarios da API' { dotnet test Site/tests/JogaBonito.Tests -c Release --nologo }

# 2 ------------------------------------------------------------ integração
$arqServ = Join-Path $env:LOCALAPPDATA 'JogaBonito\servidor-sql.txt'
$servidor = if (Test-Path $arqServ) { (Get-Content $arqServ | Select-Object -First 1).Trim() } else { '.\SQLEXPRESS' }
$env:JB_TESTE_SQL = "Server=$servidor;Trusted_Connection=True;TrustServerCertificate=True"
Etapa "Integracao (SQL Server $servidor)" { dotnet test Site/tests/JogaBonito.IntegrationTests -c Release --nologo --logger "console;verbosity=normal" }

# 3 -------------------------------------------------------------------- E2E
$python = Get-Command python -ErrorAction SilentlyContinue   # (sem "??": precisa rodar no PowerShell 5.1)
if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
if (-not $python) {
    Pular 'E2E do site (Playwright)' 'Python não encontrado (instale o Python 3 e: pip install playwright; python -m playwright install chromium)'
} else {
    # A porta 5000 precisa estar livre para a API simulada
    & powershell -NoProfile -ExecutionPolicy Bypass -File $Lancador -Acao Parar | Out-Null
    Etapa 'E2E do site (Playwright)' { & $python.Source Site/tests/e2e/test_loja.py }
}

# 4 -------------------------------------------------------- aceitação real
if (-not $python) {
    Pular 'Aceitacao contra a API real' 'Python não encontrado'
} else {
    Etapa 'Aceitacao contra a API real' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $Lancador -Acao Iniciar -SemNavegador -Silencioso
        if ($LASTEXITCODE -ne 0) { throw 'A loja não subiu (veja a mensagem do lançador acima).' }
        & $python.Source Site/tests/aceitacao/validar_loja.py http://localhost:5000
    }
}

# 5 ------------------------------------------------------------------ app
if ($PularFlutter) {
    Pular 'App Flutter' 'pedido para pular (-PularFlutter)'
} elseif (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Pular 'App Flutter' 'Flutter não encontrado (https://docs.flutter.dev/get-started/install/windows)'
} else {
    Etapa 'App Flutter (analyze, test, APK)' {
        Push-Location Mobile
        try {
            if (-not (Test-Path android)) { flutter create --project-name jogabonito_mobile --org br.unip.pim --platforms android . }
            flutter pub get
            dart run tool/preparar_android.dart
            flutter analyze --no-fatal-infos; if ($LASTEXITCODE -ne 0) { return }
            flutter test; if ($LASTEXITCODE -ne 0) { return }
            if ($UrlApk) { flutter build apk --release "--dart-define=API_URL=$UrlApk" } else { flutter build apk --release }
        } finally { Pop-Location }
    }
}

# --------------------------------------------------------------- resumo
Write-Host ''
Write-Host '======================================================================' -ForegroundColor DarkGreen
$falhou = $false
foreach ($k in $resultado.Keys) {
    $r = $resultado[$k]
    if ($null -eq $r.Ok) { Write-Host ("  PULADO  {0} - {1}" -f $k, $r.Motivo) -ForegroundColor Yellow }
    elseif ($r.Ok) { Write-Host ("  OK      {0} ({1}s)" -f $k, $r.Tempo) -ForegroundColor Green }
    else { Write-Host ("  FALHOU  {0} - {1}" -f $k, $r.Log) -ForegroundColor Red; $falhou = $true }
}
Write-Host '  Depois: rode Site/banco/conferencia.sql no SSMS para conferir o banco.' -ForegroundColor DarkGray
if ($falhou) { exit 1 } else { exit 0 }
