# ============================================================================
# JOGA BONITO — lançador da loja no Windows (API .NET 8 + SQL Server + site)
#
#   iniciar-projeto.bat            liga tudo e abre a loja (dois cliques)
#   parar-projeto.bat              desliga a API
#   ligar-com-o-windows.bat        a API passa a ligar sozinha ao entrar no Windows
#
# O que este script faz, nesta ordem:
#   1. Se a API já está no ar, só abre a loja.
#   2. Confere o .NET 8 SDK (oferece instalar pelo winget se faltar).
#   3. Encontra um SQL Server: SQL Express (.\SQLEXPRESS), instância padrão (.) ou LocalDB.
#      Se o serviço estiver parado, liga (pede permissão de administrador uma vez e o deixa
#      automático). Se não houver nenhum, oferece instalar o SQL Server Express.
#   4. Compila a API (só na primeira vez ou quando o código muda).
#   5. Sobe a API escondida (sem janela preta), com log em %LOCALAPPDATA%\JogaBonito\logs.
#   6. Espera /health/ready: banco criado, tabelas migradas e catálogo sincronizado
#      com Javascript/catalogo-local.js.
#   7. Abre http://localhost:5000 no navegador.
# ============================================================================
[CmdletBinding()]
param(
    [ValidateSet('Iniciar', 'Parar', 'Reiniciar', 'Status', 'LigarComWindows', 'DesligarComWindows', 'Atalho')]
    [string]$Acao = 'Iniciar',
    [switch]$SemNavegador,      # não abre o navegador (início automático com o Windows)
    [switch]$Rede,              # aceita conexões da rede local (celular físico com o app)
    [switch]$Silencioso,        # sem perguntas (usa só o que já está instalado)
    [int]$Porta = 5000
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$Raiz      = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Site      = Join-Path $Raiz 'Site'
$Backend   = Join-Path $Site 'backend'
$Projeto   = Join-Path $Backend 'JogaBonito.Api.csproj'
$Dados     = Join-Path $env:LOCALAPPDATA 'JogaBonito'
$PastaApi  = Join-Path $Dados 'api'
$PastaLogs = Join-Path $Dados 'logs'
$ArqPid    = Join-Path $Dados 'api.pid'
$ArqServ   = Join-Path $Dados 'servidor-sql.txt'
$ArqVersao = Join-Path $PastaApi '.versao-codigo'
$Url       = "http://localhost:$Porta"
New-Item -ItemType Directory -Force -Path $Dados, $PastaLogs | Out-Null

# ----------------------------------------------------------------- utilidades
function Escrever([string]$texto, [string]$cor = 'Gray') { Write-Host $texto -ForegroundColor $cor }
function Ok([string]$texto)    { Write-Host "  [ok] $texto" -ForegroundColor Green }
function Aviso([string]$texto) { Write-Host "  [!]  $texto" -ForegroundColor Yellow }
function Falha([string]$texto) { Write-Host "  [x]  $texto" -ForegroundColor Red }

function Perguntar([string]$pergunta) {
    if ($Silencioso) { return $false }
    $r = Read-Host "$pergunta [S/n]"
    return ($r -eq '' -or $r -match '^[sSyY]')
}

function Estado-Api {
    # 'pronta' | 'preparando' | 'falhou:<motivo>' | 'fora'
    try {
        $r = Invoke-WebRequest -Uri "$Url/health/ready" -UseBasicParsing -TimeoutSec 4
        if ($r.StatusCode -eq 200) { return 'pronta' }
    } catch {
        $resp = $_.Exception.Response
        if ($null -ne $resp) {
            try {
                $leitor = New-Object System.IO.StreamReader($resp.GetResponseStream())
                $json = $leitor.ReadToEnd() | ConvertFrom-Json
                $motivo = ($json.componentes | Where-Object { $_.status -ne 'Healthy' } | Select-Object -First 1).descricao
                if ($motivo) { return "falhou:$motivo" }
            } catch { }
            return 'preparando'
        }
    }
    return 'fora'
}

function Processo-Api {
    if (Test-Path $ArqPid) {
        $id = [int](Get-Content $ArqPid -ErrorAction SilentlyContinue | Select-Object -First 1)
        $p = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($p) { return $p }
    }
    return $null
}

function Abrir-Loja {
    # Abre direto no login; quem já está logado segue sozinho para a loja
    if (-not $SemNavegador) { Start-Process "$Url/HTML/login.html" }
}

function Resumo {
    Escrever ''
    Escrever '  ================================================================' 'DarkGreen'
    Escrever "   LOJA NO AR   $Url" 'Green'
    Escrever "   Swagger      $Url/swagger" 'Gray'
    Escrever '   Admin        admin@jogabonito.com  /  Admin@2026' 'Gray'
    Escrever '   Cliente      matheus@estudante.com /  Cliente@2026' 'Gray'
    Escrever "   Log da API   $PastaLogs\api.log" 'DarkGray'
    Escrever '   Desligar     parar-projeto.bat' 'DarkGray'
    Escrever '  ================================================================' 'DarkGreen'
}

# ------------------------------------------------------------------- .NET SDK
function Garantir-Dotnet {
    $ErrorActionPreference = 'Continue'   # stderr de programas externos não derruba o lançador (PowerShell 5.1)
    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    $temSdk8 = $false
    if ($dotnet) { $temSdk8 = [bool]((& dotnet --list-sdks 2>$null) -match '^8\.') }
    if ($temSdk8) { Ok '.NET 8 SDK encontrado'; return }

    Falha '.NET 8 SDK não encontrado.'
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget -and (Perguntar '  Instalar agora pelo winget (Microsoft.DotNet.SDK.8)?')) {
        & winget install --id Microsoft.DotNet.SDK.8 -e --accept-source-agreements --accept-package-agreements
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
        if ((& dotnet --list-sdks 2>$null) -match '^8\.') { Ok '.NET 8 SDK instalado'; return }
    }
    Start-Process 'https://dotnet.microsoft.com/download/dotnet/8.0'
    throw 'Instale o .NET 8 SDK (a página de download foi aberta) e rode iniciar-projeto.bat de novo.'
}

# ----------------------------------------------------------------- SQL Server
function Testar-Sql([string]$servidor) {
    $con = New-Object System.Data.SqlClient.SqlConnection("Server=$servidor;Database=master;Integrated Security=True;Connect Timeout=5;TrustServerCertificate=True")
    try { $con.Open(); return $true } catch { return $false } finally { $con.Dispose() }
}

function Ligar-Servico([string]$nome) {
    $svc = Get-Service -Name $nome -ErrorAction SilentlyContinue
    if (-not $svc) { return $false }
    if ($svc.Status -eq 'Running') { return $true }
    Aviso "Serviço $nome está parado - ligando..."
    try {
        Start-Service -Name $nome
    } catch {
        # Ligar serviço exige administrador: pede uma vez e já deixa o serviço automático
        $cmd = "Set-Service -Name '$nome' -StartupType Automatic; Start-Service -Name '$nome'"
        try {
            Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', $cmd
        } catch {
            Falha "Sem permissão para ligar $nome. Ligue em services.msc (SQL Server) e tente de novo."
            return $false
        }
    }
    (Get-Service -Name $nome).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
    return $true
}

function Encontrar-Sql {
    $ErrorActionPreference = 'Continue'   # stderr de programas externos não derruba o lançador (PowerShell 5.1)
    # 1. O que funcionou da última vez
    if (Test-Path $ArqServ) {
        $salvo = (Get-Content $ArqServ | Select-Object -First 1).Trim()
        if ($salvo -like '(localdb)*') { & sqllocaldb start ($salvo -replace '^\(localdb\)\\', '') 2>$null | Out-Null }
        elseif ($salvo -eq '.\SQLEXPRESS') { Ligar-Servico 'MSSQL$SQLEXPRESS' | Out-Null }
        elseif ($salvo -eq '.') { Ligar-Servico 'MSSQLSERVER' | Out-Null }
        if ($salvo -and (Testar-Sql $salvo)) { return $salvo }
    }
    # 2. SQL Server Express e instância padrão (serviços do Windows)
    foreach ($par in @(@('.\SQLEXPRESS', 'MSSQL$SQLEXPRESS'), @('.', 'MSSQLSERVER'))) {
        if ((Ligar-Servico $par[1]) -and (Testar-Sql $par[0])) { return $par[0] }
    }
    # 3. LocalDB (vem com o Visual Studio)
    if (Get-Command sqllocaldb -ErrorAction SilentlyContinue) {
        $inst = 'MSSQLLocalDB'
        if (-not ((& sqllocaldb info) -contains $inst)) { & sqllocaldb create $inst 2>$null | Out-Null }
        & sqllocaldb start $inst 2>$null | Out-Null
        if (Testar-Sql "(localdb)\$inst") { return "(localdb)\$inst" }
    }
    return $null
}

function Garantir-Sql {
    $servidor = Encontrar-Sql
    if (-not $servidor) {
        Falha 'Nenhum SQL Server encontrado neste computador.'
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget -and (Perguntar '  Instalar o SQL Server 2022 Express agora (gratuito, ~10 min)?')) {
            & winget install --id Microsoft.SQLServer.2022.Express -e --accept-source-agreements --accept-package-agreements
            $servidor = Encontrar-Sql
        }
    }
    if (-not $servidor) {
        throw 'Instale o SQL Server Express (https://www.microsoft.com/sql-server/sql-server-downloads) ou use o Docker (README, opção 2).'
    }
    Set-Content -Path $ArqServ -Value $servidor -Encoding UTF8
    Ok "SQL Server: $servidor"
    return $servidor
}

# ------------------------------------------------------------------ compilação
function Versao-Codigo {
    $arquivos = Get-ChildItem -Path $Backend -Recurse -File -Include *.cs, *.csproj, appsettings*.json |
        Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' }
    $maior = ($arquivos | Measure-Object -Property LastWriteTimeUtc -Maximum).Maximum
    return "$($arquivos.Count)-$($maior.Ticks)"
}

function Compilar-SeNecessario {
    $versao = Versao-Codigo
    $dll = Join-Path $PastaApi 'JogaBonito.Api.dll'
    if ((Test-Path $dll) -and (Test-Path $ArqVersao) -and ((Get-Content $ArqVersao) -eq $versao)) {
        Ok 'API já compilada (código sem mudanças)'
        return
    }
    Escrever '  ...  compilando a API (só na primeira vez ou quando o código muda)' 'Cyan'
    $log = Join-Path $PastaLogs 'compilacao.log'
    & dotnet publish $Projeto -c Release -o $PastaApi --nologo -v q *> $log
    if ($LASTEXITCODE -ne 0) {
        Get-Content $log -Tail 25 | ForEach-Object { Write-Host "       $_" -ForegroundColor DarkRed }
        throw "A compilação falhou. Detalhes em $log"
    }
    Set-Content -Path $ArqVersao -Value $versao -Encoding ASCII
    Ok 'API compilada'
}

# ------------------------------------------------------------------- execução
function Subir-Api([string]$servidor) {
    $logApi = Join-Path $PastaLogs 'api.log'
    if (Test-Path $logApi) { Move-Item $logApi (Join-Path $PastaLogs 'api-anterior.log') -Force }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'cmd.exe'
    $psi.Arguments = "/d /c dotnet `"$(Join-Path $PastaApi 'JogaBonito.Api.dll')`" >> `"$logApi`" 2>&1"
    $psi.WorkingDirectory = $PastaApi
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true                       # sem janela preta: a API fica em segundo plano
    $ip = if ($Rede) { '0.0.0.0' } else { 'localhost' }
    $psi.EnvironmentVariables['ASPNETCORE_ENVIRONMENT'] = 'Development'
    $psi.EnvironmentVariables['Urls'] = "http://${ip}:$Porta"
    $psi.EnvironmentVariables['Site__Raiz'] = $Site
    $psi.EnvironmentVariables['ConnectionStrings__DefaultConnection'] =
        "Server=$servidor;Database=JogaBonitoDB;Trusted_Connection=True;TrustServerCertificate=True;"
    $psi.EnvironmentVariables['DOTNET_CLI_TELEMETRY_OPTOUT'] = '1'
    $p = [System.Diagnostics.Process]::Start($psi)
    Set-Content -Path $ArqPid -Value $p.Id -Encoding ASCII
    if ($Rede) { Aviso "API aberta para a rede local (porta $Porta). Use só em rede de confiança." }
}

function Esperar-Api {
    Write-Host '  ...  preparando banco e catálogo ' -NoNewline -ForegroundColor Cyan
    $limite = (Get-Date).AddMinutes(3)
    while ((Get-Date) -lt $limite) {
        $estado = Estado-Api
        if ($estado -eq 'pronta') { Write-Host ''; Ok 'API pronta (banco criado e catálogo sincronizado)'; return }
        if ($estado -like 'falhou:*') {
            Write-Host ''
            Falha "O banco não ficou pronto: $($estado.Substring(7))"
            throw "Veja o log em $PastaLogs\api.log"
        }
        if (-not (Processo-Api)) {
            Write-Host ''
            Falha 'A API fechou durante a inicialização. Últimas linhas do log:'
            Get-Content (Join-Path $PastaLogs 'api.log') -Tail 20 -ErrorAction SilentlyContinue |
                ForEach-Object { Write-Host "       $_" -ForegroundColor DarkRed }
            throw 'Corrija o problema acima e rode iniciar-projeto.bat de novo.'
        }
        Write-Host '.' -NoNewline -ForegroundColor Cyan
        Start-Sleep -Seconds 2
    }
    Write-Host ''
    throw "A API demorou mais de 3 minutos para ficar pronta. Veja $PastaLogs\api.log"
}

function Porta-Ocupada {
    try {
        $c = Get-NetTCPConnection -LocalPort $Porta -State Listen -ErrorAction Stop | Select-Object -First 1
        if ($c) { return (Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue) }
    } catch { }
    return $null
}

# ------------------------------------------------------------------ fotos
# Fotos novas em Site\IMG\Produtos\<id>\ (qualquer nome/formato) viram 1.jpg, 2.jpg... até 1200 px,
# entram no catálogo e no seed.sql. Precisa de Python; sem ele, a API usa as fotos como estão.
function Organizar-Fotos {
    $ErrorActionPreference = 'Continue'   # stderr de programas externos não derruba o lançador (PowerShell 5.1)
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
    if (-not $py -or $py.Source -like '*WindowsApps*') { return }   # atalho da Microsoft Store não é o Python
    & $py.Source -c "import PIL" 2>$null
    if ($LASTEXITCODE -ne 0) {
        & $py.Source -m pip install --user --quiet pillow 2>$null | Out-Null
    }
    try { $saida = & $py.Source (Join-Path $Site 'ferramentas\gerar_catalogo.py') 2>&1 } catch { $saida = @() }
    if ($LASTEXITCODE -eq 0) {
        $saida | Where-Object { $_ -match 'organizada' } | ForEach-Object { Ok ($_.ToString().Trim()) }
    } else {
        Aviso 'Não consegui organizar as fotos agora (a loja usa as fotos como estão).'
    }
}

# ---------------------------------------------------------------------- ações
function Iniciar {
    Escrever ''
    Escrever '  JOGA BONITO - ligando a loja' 'Green'
    Escrever ''
    Organizar-Fotos
    $estado = Estado-Api
    if ($estado -eq 'pronta') { Ok 'A API já está no ar'; Resumo; Abrir-Loja; return }

    $dono = Porta-Ocupada
    if ($dono -and -not (Processo-Api)) {
        throw "A porta $Porta está em uso por '$($dono.ProcessName)' (PID $($dono.Id)). Feche esse programa ou rode parar-projeto.bat."
    }
    # API já ligada por este lançador (ex.: entrou no Windows agora) e ainda preparando o banco: só espera
    if ((Processo-Api) -and (Test-Path $ArqVersao) -and ((Get-Content $ArqVersao) -eq (Versao-Codigo))) {
        Ok 'A API já está ligando (início automático com o Windows)'
        Esperar-Api
        Resumo
        Abrir-Loja
        Configurar-PrimeiraVez
        return
    }
    if (Processo-Api) { Parar -Quieto }

    Garantir-Dotnet
    $servidor = Garantir-Sql
    Compilar-SeNecessario
    Subir-Api $servidor
    Esperar-Api
    Resumo
    Abrir-Loja
    Configurar-PrimeiraVez
}

# Na primeira vez que a loja sobe com sucesso: liga com o Windows e cria o atalho na área de trabalho.
# Daí em diante a API já está no ar quando o computador liga — é só abrir a loja e fazer login.
function Configurar-PrimeiraVez {
    $marca = Join-Path $Dados 'configurado.txt'
    if ($Silencioso -or (Test-Path $marca)) { return }
    Escrever ''
    Ligar-Com-Windows
    Criar-Atalho
    Set-Content -Path $marca -Value (Get-Date -Format 's') -Encoding ASCII
}

function Criar-Atalho {
    $atalho = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Joga Bonito.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($atalho)
    $lnk.TargetPath = Join-Path $Raiz 'iniciar-projeto.bat'
    $lnk.WorkingDirectory = $Raiz
    $lnk.WindowStyle = 7                                   # janela minimizada: some sozinha quando a loja abre
    $icone = Join-Path $Site 'IMG\jogabonito.ico'
    if (Test-Path $icone) { $lnk.IconLocation = $icone }
    $lnk.Description = 'Abre a loja Joga Bonito (liga a API se precisar)'
    $lnk.Save()
    Ok 'Atalho "Joga Bonito" criado na área de trabalho.'
}

function Parar([switch]$Quieto) {
    $ErrorActionPreference = 'Continue'   # stderr de programas externos não derruba o lançador (PowerShell 5.1)
    $p = Processo-Api
    if ($p) {
        & taskkill /PID $p.Id /T /F 2>$null | Out-Null
        if (-not $Quieto) { Ok 'API desligada' }
    } elseif (-not $Quieto) {
        Aviso 'A API não estava ligada por este lançador.'
    }
    Remove-Item $ArqPid -ErrorAction SilentlyContinue
}

function Status {
    $estado = Estado-Api
    switch -Wildcard ($estado) {
        'pronta'    { Ok "Loja no ar em $Url" }
        'preparando'{ Aviso 'API ligada, preparando o banco...' }
        'falhou:*'  { Falha "API ligada, mas o banco falhou: $($estado.Substring(7))" }
        default     { Aviso 'API desligada' }
    }
    if (Test-Path $ArqServ) { Escrever "  SQL Server: $(Get-Content $ArqServ)" }
    $atalho = Join-Path ([Environment]::GetFolderPath('Startup')) 'Joga Bonito - API.lnk'
    if (Test-Path $atalho) { Escrever '  Liga sozinha com o Windows: sim' } else { Escrever '  Liga sozinha com o Windows: não' }
}

function Ligar-Com-Windows {
    # Atalho na pasta Inicializar do usuário: não precisa de administrador e é fácil de remover
    $atalho = Join-Path ([Environment]::GetFolderPath('Startup')) 'Joga Bonito - API.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($atalho)
    $lnk.TargetPath = (Get-Command powershell).Source
    $lnk.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Acao Iniciar -SemNavegador -Silencioso"
    $lnk.WorkingDirectory = $Raiz
    $lnk.WindowStyle = 7
    $lnk.Description = 'Liga a API da loja Joga Bonito ao entrar no Windows'
    $lnk.Save()
    Ok 'Pronto: a API da Joga Bonito vai ligar sozinha sempre que você entrar no Windows.'
    Escrever '       Para desfazer: desligar-com-o-windows.bat' 'DarkGray'
}

function Desligar-Com-Windows {
    $atalho = Join-Path ([Environment]::GetFolderPath('Startup')) 'Joga Bonito - API.lnk'
    if (Test-Path $atalho) { Remove-Item $atalho; Ok 'A API não liga mais sozinha com o Windows.' }
    else { Aviso 'O início automático não estava ativado.' }
}

try {
    switch ($Acao) {
        'Iniciar'            { Iniciar }
        'Parar'              { Parar }
        'Reiniciar'          { Parar -Quieto; Iniciar }
        'Status'             { Status }
        'LigarComWindows'    { Ligar-Com-Windows; if (-not (Processo-Api)) { $SemNavegador = $true; Iniciar } }
        'DesligarComWindows' { Desligar-Com-Windows }
        'Atalho'             { Criar-Atalho }
    }
    exit 0
} catch {
    Escrever ''
    Falha $_.Exception.Message
    exit 1
}
