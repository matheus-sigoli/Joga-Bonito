#!/usr/bin/env python3
# ============================================================================
# JOGA BONITO — verificação de segurança do ambiente publicado
#
#   python3 Site/ferramentas/verificar_publicacao.py https://jogabonito-api.azurewebsites.net
#
# Confere, contra o endereço real: HTTPS e HSTS, cabeçalhos de segurança, CSP,
# Swagger fechado, CORS recusando outras origens, /health/ready saudável e
# rotas protegidas exigindo login. Sai com código 1 se algo falhar (usado no CI).
# Só usa a biblioteca padrão do Python.
# ============================================================================
import json
import sys
import urllib.error
import urllib.request

if len(sys.argv) != 2:
    sys.exit("Uso: verificar_publicacao.py https://endereco-da-loja")
BASE = sys.argv[1].rstrip("/")
resultados = []


class SemRedirecionar(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def pedir(caminho, metodo="GET", cabecalhos=None, base=BASE, seguir=True):
    req = urllib.request.Request(base + caminho, method=metodo, headers=cabecalhos or {})
    abrir = urllib.request.build_opener() if seguir else urllib.request.build_opener(SemRedirecionar)
    try:
        with abrir.open(req, timeout=20) as r:
            return r.status, {k.lower(): v for k, v in r.headers.items()}, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, {k.lower(): v for k, v in e.headers.items()}, e.read().decode("utf-8", "replace")


def checar(nome, ok, detalhe=""):
    resultados.append(ok)
    print(f"[{'OK ' if ok else 'FALHA'}] {nome}" + (f" — {detalhe}" if detalhe else ""))


# 1. HTTPS
checar("Endereço usa HTTPS", BASE.startswith("https://"), BASE)
if BASE.startswith("https://"):
    st, cab, _ = pedir("/HTML/inicial.html", base="http://" + BASE[len("https://"):], seguir=False)
    checar("HTTP redireciona para HTTPS", st in (301, 302, 307, 308) and cab.get("location", "").startswith("https://"),
           f"status {st}")

# 2. Página da loja e cabeçalhos
st, cab, _ = pedir("/HTML/inicial.html")
checar("Loja responde", st == 200, f"status {st}")
checar("HSTS (Strict-Transport-Security)", "max-age" in cab.get("strict-transport-security", ""))
checar("Content-Security-Policy sem scripts inline", "script-src 'self'" in cab.get("content-security-policy", "")
       and "'unsafe-inline'" not in cab.get("content-security-policy", "").split("script-src")[1].split(";")[0])
checar("X-Content-Type-Options: nosniff", cab.get("x-content-type-options") == "nosniff")
checar("X-Frame-Options", cab.get("x-frame-options", "").upper() in ("SAMEORIGIN", "DENY"))
checar("Referrer-Policy", bool(cab.get("referrer-policy")))

# 3. Swagger fechado em produção
st, _, _ = pedir("/swagger/index.html")
checar("Swagger fechado", st == 404, f"status {st}")

# 4. CORS: outra origem não recebe permissão
st, cab, _ = pedir("/api/produtos", "OPTIONS", {"Origin": "https://site-malicioso.example",
                                                "Access-Control-Request-Method": "GET"})
checar("CORS recusa origem desconhecida", "access-control-allow-origin" not in cab,
       cab.get("access-control-allow-origin", "sem cabeçalho"))

# 5. Saúde e banco
st, _, corpo = pedir("/health/ready")
try:
    estado = json.loads(corpo)
except ValueError:
    estado = {}
checar("/health/ready saudável (API + esquema + catálogo)", st == 200 and estado.get("status") == "Healthy",
       "; ".join(f"{c.get('nome')}: {c.get('descricao')}" for c in estado.get("componentes", [])) or corpo[:120])
checar("/health/ready não expõe detalhes da infraestrutura ao público", "componentes" not in estado,
       "mostra nomes de objetos/mensagens do banco sem login")
st, _, _ = pedir("/health/live")
checar("/health/live responde", st == 200, f"status {st}")

# 6. Rotas protegidas
st, _, _ = pedir("/api/pedidos/meus")
checar("Pedidos exigem login (401)", st == 401, f"status {st}")
st, _, _ = pedir("/api/admin/dashboard", cabecalhos={"Authorization": "Bearer token-falso"})
checar("Painel admin recusa token falso (401)", st == 401, f"status {st}")

# 7. Contas de demonstração não existem em produção
req = urllib.request.Request(BASE + "/api/auth/login", method="POST",
                             data=json.dumps({"email": "admin@jogabonito.com", "senha": "Admin@2026"}).encode(),
                             headers={"Content-Type": "application/json"})
try:
    with urllib.request.urlopen(req, timeout=20) as r:
        st = r.status
except urllib.error.HTTPError as e:
    st = e.code
checar("Senha de demonstração do admin NÃO funciona", st in (401, 423, 429), f"status {st}")

falhas = resultados.count(False)
print(f"\n{len(resultados) - falhas} de {len(resultados)} verificações aprovadas.")
sys.exit(1 if falhas else 0)
