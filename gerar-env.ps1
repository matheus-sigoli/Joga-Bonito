# Gera o .env do docker-compose com segredos aleatórios e exclusivos deste computador.
# Uso: powershell -ExecutionPolicy Bypass -File gerar-env.ps1
# Se o .env já existe, só acrescenta o que faltar (nunca troca um segredo existente:
# trocar DADOS_CHAVE tornaria ilegíveis os endereços já cifrados no banco).
Set-Location $PSScriptRoot

function Aleatorio([int]$n) {
  $bytes = New-Object byte[] 96
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '').Substring(0, $n)
}
function Chave32 {
  $bytes = New-Object byte[] 32
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  [Convert]::ToBase64String($bytes)
}

$atual = if (Test-Path .env) { Get-Content .env } else { @() }
$novas = @()
if (-not ($atual -match '^SQL_SA_PASSWORD=.+')) { $novas += "SQL_SA_PASSWORD=Jb#$(Aleatorio 20)9a" }
if (-not ($atual -match '^JWT_CHAVE=.+'))       { $novas += "JWT_CHAVE=$(Aleatorio 64)" }
if (-not ($atual -match '^DADOS_CHAVE=.+'))     { $novas += "DADOS_CHAVE=$(Chave32)" }

if ($novas.Count -eq 0) { Write-Host ".env completo - nada a fazer."; exit 0 }
Add-Content -Path .env -Value $novas -Encoding ascii
Write-Host ".env atualizado ($($novas.Count) segredo(s) novo(s)). Guarde uma copia de DADOS_CHAVE em lugar seguro."
Write-Host "Suba com: docker compose up -d --build"
