#!/usr/bin/env python3
# ============================================================================
# JOGA BONITO — validação de aceitação contra a API REAL (local ou publicada)
#
# Percorre a loja inteira pela API, como cliente e como administrador, e confere
# o efeito de cada operação nos dados (estoque, pedidos, avaliações, contas):
#   sessão (cadastro, login, cookie do site, CSRF, logout) · 36 produtos e filtros ·
#   cupons, frete e Joga Junto · compra, histórico, cancelamento e devolução do estoque ·
#   permissões e IDOR · painel admin (estoque, produtos, status, moderação, indicadores) ·
#   LGPD (exportar e excluir conta)
#
# Uso:
#   python Site/tests/aceitacao/validar_loja.py http://localhost:5000
#   python Site/tests/aceitacao/validar_loja.py https://<loja>.azurewebsites.net \
#          --admin-email admin@... --admin-senha ... --confirmo-producao
#
# Só usa a biblioteca padrão do Python 3.10+. Cria dois clientes de teste, pedidos e um
# produto de teste; no fim cancela os pedidos (o estoque volta), desativa o produto e
# exclui as contas (LGPD). Os pedidos cancelados ficam no histórico, anônimos.
# Para conferir o banco depois: Site/banco/conferencia.sql (SSMS / Azure Data Studio).
# ============================================================================
from __future__ import annotations

import argparse
import http.cookiejar
import json
import secrets
from decimal import ROUND_HALF_UP, Decimal
import sys
import time
import urllib.error
import urllib.request
from urllib.parse import urlencode, urlparse

# ----------------------------------------------------------------- relatório
resultados: list[tuple[str, bool, str]] = []
secao_atual = ""


def secao(nome: str) -> None:
    global secao_atual
    secao_atual = nome
    print(f"\n== {nome}")


def checar(descricao: str, ok: bool, detalhe: str = "") -> bool:
    resultados.append((f"{secao_atual} › {descricao}", bool(ok), detalhe))
    print(f"  [{'ok' if ok else 'FALHOU'}] {descricao}" + ("" if ok or not detalhe else f" — {detalhe}"))
    return bool(ok)


class Pular(Exception):
    """Interrompe uma seção quando um passo de que as próximas dependem falhou."""


# ------------------------------------------------------------------- cliente HTTP
class Cliente:
    """Cliente da API. modo='app' usa Authorization: Bearer; modo='site' usa o cookie HttpOnly."""

    def __init__(self, base: str, modo: str = "app"):
        self.base = base.rstrip("/")
        self.modo = modo
        self.token: str | None = None
        self.cookies = http.cookiejar.CookieJar()
        self.abridor = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.cookies))

    def pedir(self, metodo: str, caminho: str, corpo=None, csrf: bool = True, cabecalhos: dict | None = None,
              tentativas_429: int = 2):
        h = {"Accept": "application/json"}
        if corpo is not None:
            h["Content-Type"] = "application/json"
        if self.modo == "site":
            h["X-JB-Cliente"] = "web"
            if csrf:
                h["X-JB-Requisicao"] = "1"
        elif self.token:
            h["Authorization"] = f"Bearer {self.token}"
        h.update(cabecalhos or {})
        dados = json.dumps(corpo).encode() if corpo is not None else None
        req = urllib.request.Request(self.base + caminho, data=dados, method=metodo, headers=h)
        try:
            with self.abridor.open(req, timeout=60) as r:
                texto = r.read().decode("utf-8")
                return r.status, (json.loads(texto) if texto.strip().startswith(("{", "[")) else texto), r.headers
        except urllib.error.HTTPError as e:
            texto = e.read().decode("utf-8", "replace")
            if e.code == 429 and tentativas_429 > 0:
                print("  ...  limite de requisições atingido (proteção da API); aguardando 61 s")
                time.sleep(61)
                return self.pedir(metodo, caminho, corpo, csrf, cabecalhos, tentativas_429 - 1)
            try:
                corpo_erro = json.loads(texto)
            except ValueError:
                corpo_erro = {"mensagem": texto[:200]}
            return e.code, corpo_erro, e.headers

    def get(self, c, **k): return self.pedir("GET", c, **k)
    def post(self, c, corpo=None, **k): return self.pedir("POST", c, corpo if corpo is not None else {}, **k)
    def put(self, c, corpo, **k): return self.pedir("PUT", c, corpo, **k)
    def delete(self, c, **k): return self.pedir("DELETE", c, **k)

    def entrar(self, email: str, senha: str) -> tuple[int, dict]:
        st, r, _ = self.post("/api/auth/login", {"email": email, "senha": senha})
        if st == 200 and self.modo == "app":
            self.token = r.get("token")
        return st, r


def msg(r) -> str:
    return (r or {}).get("mensagem", "") if isinstance(r, dict) else str(r)[:120]


ENDERECO = {"cep": "01310100", "rua": "Avenida Paulista", "numero": "1000", "complemento": "Teste de aceitação",
            "bairro": "Bela Vista", "cidade": "São Paulo", "estado": "SP"}


def pedido(produto_id, tamanho, qtd=1, cupom=None):
    return {"itens": [{"produtoId": produto_id, "tamanho": tamanho, "quantidade": qtd}],
            "formaPagamento": "PIX", "parcelas": 1, "cupom": cupom, "endereco": ENDERECO, "origem": "Web"}


def saldo(api: Cliente, produto_id: int, tamanho: str) -> int:
    st, d, _ = api.get(f"/api/produtos/{produto_id}")
    if st != 200:
        raise Pular(f"produto {produto_id} indisponível ({st})")
    return next(t["quantidade"] for t in d["tamanhos"] if t["tamanho"] == tamanho)


def escolher_tamanho(api: Cliente, produto_id: int, minimo: int = 3) -> str:
    st, d, _ = api.get(f"/api/produtos/{produto_id}")
    for t in d.get("tamanhos", []):
        if t["quantidade"] >= minimo:
            return t["tamanho"]
    raise Pular(f"produto {produto_id} sem tamanho com {minimo}+ peças")


def jogajunto(valor: float) -> float:
    v = Decimal(str(round(valor, 2))) * Decimal("0.01")
    return float(v.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)) if v > 0 else 0.0


def novo_email(prefixo: str) -> str:
    return f"{prefixo}-{secrets.token_hex(4)}@aceitacao.jogabonito.test"


SENHA = "Gol de placa 2026"


# =================================================================== roteiro
def main() -> int:
    ap = argparse.ArgumentParser(description="Validação de aceitação da Joga Bonito contra a API real.")
    ap.add_argument("url", help="ex.: http://localhost:5000 ou https://<loja>.azurewebsites.net")
    ap.add_argument("--admin-email", default="admin@jogabonito.com")
    ap.add_argument("--admin-senha", default="Admin@2026")
    ap.add_argument("--confirmo-producao", action="store_true",
                    help="obrigatório fora do localhost: o roteiro cria clientes, pedidos e um produto de teste")
    args = ap.parse_args()

    host = urlparse(args.url).hostname or ""
    local = host in ("localhost", "127.0.0.1") or host.startswith(("192.168.", "10."))
    if not local and not args.confirmo_producao:
        print("Este roteiro cria dados de teste (depois cancelados/anonimizados). Para rodar em "
              f"{args.url}, acrescente --confirmo-producao e informe --admin-email/--admin-senha.")
        return 2

    base = args.url.rstrip("/")
    anonimo = Cliente(base)
    cli = Cliente(base)
    outro = Cliente(base)
    adm = Cliente(base)
    email_cli, email_outro = novo_email("cliente"), novo_email("outro")
    pedidos_abertos: list[tuple[Cliente, int]] = []
    produto_teste: int | None = None
    estoque_restaurar: tuple[int, str, int] | None = None

    print(f"Joga Bonito — validação de aceitação em {base}")

    # ------------------------------------------------------------ 0. disponibilidade
    secao("API no ar")
    st, d, _ = anonimo.get("/health/ready")
    if not checar("/health/ready saudável", st == 200 and isinstance(d, dict) and d.get("status") == "Healthy", f"{st} {d}"):
        return resumo()

    # ------------------------------------------------------------ 1. sessão
    secao("Cadastro, login, sessão e logout")
    try:
        st, r, _ = anonimo.post("/api/auth/cadastro", {"nome": "Cliente Aceitação", "email": email_cli,
                                                       "senha": SENHA, "aceiteLgpd": True})
        if not checar("cadastro de cliente novo (201)", st == 201, f"{st} {msg(r)}"):
            raise Pular("sem cliente")
        st, r, _ = anonimo.post("/api/auth/cadastro", {"nome": "Cliente Aceitação", "email": email_cli,
                                                       "senha": SENHA, "aceiteLgpd": True})
        checar("e-mail repetido é recusado (400)", st == 400, f"{st} {msg(r)}")
        st, r, _ = anonimo.post("/api/auth/cadastro", {"nome": "Cliente Fraco", "email": novo_email("fraco"),
                                                       "senha": "senha123", "aceiteLgpd": True})
        checar("senha comum é recusada (400)", st == 400, f"{st} {msg(r)}")
        st, r, _ = anonimo.post("/api/auth/cadastro", {"nome": "Sem Aceite", "email": novo_email("lgpd"),
                                                       "senha": SENHA, "aceiteLgpd": False})
        checar("cadastro sem aceite da política é recusado (400)", st == 400, f"{st} {msg(r)}")

        st, r = Cliente(base).entrar(email_cli, "senha-errada-1")
        checar("senha errada: 401 com mensagem genérica", st == 401 and "incorretos" in msg(r), f"{st} {msg(r)}")

        st, r = cli.entrar(email_cli, SENHA)
        checar("login do app devolve token", st == 200 and bool(cli.token), f"{st} {msg(r)}")
        st, me, _ = cli.get("/api/auth/me")
        checar("/me identifica o cliente", st == 200 and me.get("email") == email_cli, f"{st} {me}")

        site = Cliente(base, "site")
        st, r = site.entrar(email_cli, SENHA)
        cookie = next((c for c in site.cookies if c.name in ("jb_sessao", "__Host-jb_sessao")), None)
        checar("login do site: sessão em cookie, sem token no corpo",
               st == 200 and cookie is not None and not r.get("token"), f"{st} token={'sim' if r.get('token') else 'não'}")
        if cookie is not None:
            checar("cookie HttpOnly", any(k.lower() == "httponly" for k in cookie._rest), str(cookie._rest))
            if base.startswith("https://"):
                checar("cookie Secure com prefixo __Host- (HTTPS)", cookie.secure and cookie.name.startswith("__Host-"), cookie.name)
        st, me, _ = site.get("/api/auth/me")
        checar("site usa a sessão do cookie", st == 200, f"{st}")
        st, r, _ = site.post("/api/auth/sair-de-todos", csrf=False)
        checar("escrita sem cabeçalho anti-CSRF é recusada (403)", st == 403, f"{st} {msg(r)}")
        st, _, _ = site.post("/api/auth/sair")
        st2, _, _ = site.get("/api/auth/me")
        checar("logout apaga a sessão do site", st == 204 and st2 == 401, f"sair={st} me={st2}")
        st, r, _ = anonimo.post("/api/auth/login", {"email": "x@y.com", "senha": "a"},
                                cabecalhos={"Origin": "https://site-malicioso.example"})
        checar("requisição vinda de outro site é recusada (403)", st == 403, f"{st}")

        st, r, _ = anonimo.post("/api/auth/cadastro", {"nome": "Outro Cliente", "email": email_outro,
                                                       "senha": SENHA, "aceiteLgpd": True})
        outro.entrar(email_outro, SENHA)
    except Pular as e:
        checar("seção interrompida", False, str(e))

    # ------------------------------------------------------------ 2. catálogo
    secao("Catálogo: 36 produtos, detalhes, tamanhos e filtros")
    st, produtos, _ = anonimo.get("/api/produtos?ordem=nome")
    ids = {p["id"] for p in produtos} if st == 200 else set()
    checar("lista com os 36 produtos (IDs 1 a 36)", set(range(1, 37)) <= ids, f"{st}, faltam {sorted(set(range(1, 37)) - ids)}")
    falhas = []
    for pid in range(1, 37):
        st, d, _ = anonimo.get(f"/api/produtos/{pid}")
        if st != 200:
            falhas.append(f"{pid}: HTTP {st}")
            continue
        p, tams = d["produto"], [t["tamanho"] for t in d["tamanhos"]]
        chut = p["categoriaSlug"] == "chuteiras"
        esperado = [str(n) for n in range(37, 45)] if chut else ["P", "M", "G", "GG", "XG"]
        if sorted(tams, key=lambda t: esperado.index(t) if t in esperado else 99) != esperado:
            falhas.append(f"{pid}: tamanhos {tams}")
        if not d["imgs"] or not p["img"].startswith("../IMG/"):
            falhas.append(f"{pid}: imagens")
        if p["precoFinal"] <= 0 or (chut and not (p.get("marca") and p.get("solado"))):
            falhas.append(f"{pid}: preço/marca/solado")
        if p["estoque"] != sum(t["quantidade"] for t in d["tamanhos"]):
            falhas.append(f"{pid}: estoque total ≠ soma dos tamanhos")
    checar("detalhe de cada produto: tamanhos certos, imagens, preço, estoque", not falhas, "; ".join(falhas[:6]))
    for slug in ("temporada-2026", "retro", "chuteiras"):
        st, l, _ = anonimo.get(f"/api/produtos?categoria={slug}")
        checar(f"categoria {slug}: 12 produtos", st == 200 and len(l) >= 12 and all(p["categoriaSlug"] == slug for p in l), f"{st} {len(l) if st == 200 else ''}")
    st, l, _ = anonimo.get("/api/produtos?categoria=chuteiras&linha=Futsal")
    checar("filtro de linha (Futsal: 4)", st == 200 and len(l) >= 4 and all(p["linha"] == "Futsal" for p in l), f"{len(l)}")
    st, l, _ = anonimo.get("/api/produtos?marca=Nike")
    checar("filtro de marca (Nike)", st == 200 and l and all(p["marca"] == "Nike" for p in l), f"{len(l)}")
    st, l, _ = anonimo.get("/api/produtos?precoMax=300")
    checar("filtro de preço máximo", st == 200 and l and all(p["precoFinal"] <= 300 for p in l), f"{len(l)}")
    st, l, _ = anonimo.get("/api/produtos?ordem=menor-preco")
    precos = [p["precoFinal"] for p in l]
    checar("ordenação por menor preço", st == 200 and precos == sorted(precos))
    st, l, _ = anonimo.get("/api/produtos?" + urlencode({"busca": "Brasil"}))
    checar("busca por 'Brasil'", st == 200 and any(p["id"] == 1 for p in l) and any(p["id"] == 13 for p in l))
    st, l, _ = anonimo.get("/api/produtos?" + urlencode({"busca": "'; DROP TABLE Produtos--"}))
    checar("busca maliciosa não quebra nada (lista vazia, 200)", st == 200 and l == [], f"{st}")
    st, _, _ = anonimo.get("/api/produtos/999999")
    checar("produto inexistente: 404", st == 404, f"{st}")

    # ------------------------------------------------------------ 3. compra
    secao("Cupom, frete, Joga Junto, compra, histórico e cancelamento")
    try:
        if not cli.token:
            raise Pular("cliente não logado")
        st, c, _ = anonimo.post("/api/cupons/validar", {"codigo": "BEMVINDO10", "subtotal": 400})
        checar("cupom BEMVINDO10 válido", st == 200 and c.get("valido"), f"{st} {c}")
        st, c, _ = anonimo.post("/api/cupons/validar", {"codigo": "NAOEXISTE99", "subtotal": 400})
        checar("cupom inexistente recusado", st == 200 and not c.get("valido"), f"{st} {c}")

        tam = escolher_tamanho(anonimo, 13)                       # Brasil 1994 (R$ 299,90)
        st, s, _ = cli.post("/api/pedidos/simular", {"itens": [{"produtoId": 13, "tamanho": tam, "quantidade": 1}]})
        checar("frete grátis a partir de R$ 299", st == 200 and s["frete"] == 0, f"{st} {s}")
        st, s, _ = cli.post("/api/pedidos/simular", {"itens": [{"produtoId": 13, "tamanho": tam, "quantidade": 1}], "cupom": "BEMVINDO10"})
        # Igual a dbo.fn_CalcularJogaJunto: ROUND(valor * 0,01; 2), meio para cima (o round() do Python arredonda para o par)
        esperado_jj = jogajunto(s["subtotal"] - s["desconto"]) if st == 200 else None
        checar("cupom de 10% e frete de R$ 19,90 abaixo de R$ 299",
               st == 200 and abs(s["desconto"] - round(s["subtotal"] * 0.10, 2)) < 0.01 and s["frete"] == 19.9, f"{s}")
        checar("Joga Junto = 1% dos produtos com desconto, sem frete", st == 200 and abs(s.get("jogaJunto", -1) - esperado_jj) < 0.011,
               f"{s.get('jogaJunto')} esperado {esperado_jj}")

        antes = saldo(anonimo, 13, tam)
        st, p, _ = cli.post("/api/pedidos", pedido(13, tam, 1, "BEMVINDO10"))
        if not checar("pedido criado (201)", st == 201 and p.get("pedidoId"), f"{st} {msg(p)}"):
            raise Pular("sem pedido")
        pid = p["pedidoId"]
        pedidos_abertos.append((cli, pid))
        checar("pedido grava o Joga Junto calculado", abs(p.get("jogaJunto", -1) - esperado_jj) < 0.011, f"{p.get('jogaJunto')}")
        checar("estoque baixou 1 peça", saldo(anonimo, 13, tam) == antes - 1, f"antes {antes}")
        st, meus, _ = cli.get("/api/pedidos/meus")
        checar("pedido aparece no histórico do cliente", st == 200 and any(x["id"] == pid for x in meus))
        st, det, _ = cli.get(f"/api/pedidos/{pid}")
        checar("detalhe: itens, total e linha do tempo",
               st == 200 and det["itens"][0]["produtoId"] == 13 and abs(det["total"] - p["total"]) < 0.01 and det["historico"],
               f"{st}")
        st, _, _ = outro.get(f"/api/pedidos/{pid}")
        checar("outro cliente não vê o pedido (404)", st == 404, f"{st} (403 = versão antiga da API)")
        st, _, _ = outro.post(f"/api/pedidos/{pid}/cancelar")
        checar("outro cliente não cancela o pedido", st in (403, 404), f"{st}")

        st, _, _ = cli.post(f"/api/pedidos/{pid}/cancelar")
        checar("cliente cancela antes da separação (204)", st == 204, f"{st}")
        pedidos_abertos.remove((cli, pid))
        checar("estoque voltou ao cancelar", saldo(anonimo, 13, tam) == antes, f"antes {antes}")
        st, det, _ = cli.get(f"/api/pedidos/{pid}")
        checar("status Cancelado com registro no histórico",
               det.get("status") == "Cancelado" and any(h["status"] == "Cancelado" for h in det.get("historico", [])))

        dois = pedido(13, tam, 1)
        dois["itens"] = dois["itens"] * 2                          # mesma peça em duas linhas
        st, p2, _ = cli.post("/api/pedidos", dois)
        if checar("mesma peça em duas linhas vira um item só", st == 201 and saldo(anonimo, 13, tam) == antes - 2, f"{st} {msg(p2)}"):
            st, _, _ = cli.post(f"/api/pedidos/{p2['pedidoId']}/cancelar")
            checar("cancelamento devolve as duas peças", st == 204 and saldo(anonimo, 13, tam) == antes, f"{st}")

        st, r, _ = cli.post("/api/pedidos", pedido(13, tam, 999))
        checar("compra acima do estoque é recusada", st == 400, f"{st} {msg(r)}")
        st, r, _ = cli.post("/api/pedidos", {**pedido(13, tam, 1), "itens": [{"produtoId": 13, "tamanho": tam, "quantidade": 1, "precoUnitario": 0.01}]})
        if st == 201:
            pedidos_abertos.append((cli, r["pedidoId"]))
        checar("preço enviado pelo cliente é ignorado (preço do banco)", st != 201 or r["subtotal"] >= 299.9, f"{st} {r}")
    except Pular as e:
        checar("seção interrompida", False, str(e))

    # ------------------------------------------------------------ 4. admin
    secao("Permissões e painel administrativo")
    st, _, _ = anonimo.get("/api/admin/dashboard")
    checar("sem login: 401 no painel", st == 401, f"{st}")
    st, _, _ = cli.get("/api/admin/dashboard")
    checar("cliente: 403 no painel", st == 403, f"{st}")
    st, _, _ = cli.put("/api/admin/estoque", {"produtoId": 13, "tamanho": "M", "quantidade": 999})
    checar("cliente não altera estoque (403)", st == 403, f"{st}")
    try:
        st, r = adm.entrar(args.admin_email, args.admin_senha)
        if not checar("login do administrador", st == 200 and r["usuario"]["role"] == "Admin", f"{st} {msg(r)}"):
            raise Pular("sem admin")
        st, d, _ = adm.get("/api/admin/dashboard")
        checar("indicadores do painel", st == 200 and d["totalProdutos"] >= 36 and "totalJogaJunto" in d and "avaliacoesPendentes" in d, f"{st}")
        # Estoque
        tam = escolher_tamanho(anonimo, 8, 1)
        original = saldo(anonimo, 8, tam)
        estoque_restaurar = (8, tam, original)
        st, _, _ = adm.put("/api/admin/estoque", {"produtoId": 8, "tamanho": tam, "quantidade": original + 7})
        checar("admin ajusta o estoque e a loja mostra o novo saldo", st == 204 and saldo(anonimo, 8, tam) == original + 7, f"{st}")
        st, aud, _ = adm.get("/api/admin/estoque/auditoria?limite=20")
        checar("ajuste registrado na auditoria (trigger)", st == 200 and any(
            a["produtoId"] == 8 and a["tamanho"] == tam and a["qtdNova"] == original + 7 for a in aud))
        st, _, _ = adm.put("/api/admin/estoque", {"produtoId": 8, "tamanho": tam, "quantidade": -1})
        checar("estoque negativo é recusado", st == 400, f"{st}")
        adm.put("/api/admin/estoque", {"produtoId": 8, "tamanho": tam, "quantidade": original})
        estoque_restaurar = None
        # Produtos
        st, cats, _ = anonimo.get("/api/categorias")
        retro = next(c["id"] for c in cats if c["slug"] == "retro")
        novo = {"categoriaId": retro, "nome": "Camisa Teste de Aceitação", "modelo": "Coleção Retrô", "linha": "Clube",
                "equipe": "Teste FC", "ano": 1999, "descricao": "Produto criado pelo roteiro de aceitação; é desativado no fim.",
                "preco": 199.9, "precoPromocional": None, "imagem": "../IMG/LOGO 2.png", "destaque": False, "imagens": None}
        st, r, _ = adm.post("/api/admin/produtos", {**novo, "imagem": "javascript:alert(1)"})
        checar("imagem fora da pasta IMG é recusada", st == 400, f"{st} {msg(r)}")
        st, r, _ = adm.post("/api/admin/produtos", novo)
        if checar("admin cadastra produto (201)", st == 201 and r.get("id"), f"{st} {msg(r)}"):
            produto_teste = r["id"]
            st, _, _ = adm.put(f"/api/admin/produtos/{produto_teste}", {**novo, "preco": 189.9})
            st2, d, _ = anonimo.get(f"/api/produtos/{produto_teste}")
            checar("alteração de preço aparece na loja", st == 204 and st2 == 200 and d["produto"]["precoFinal"] == 189.9, f"{st}/{st2}")
            st, _, _ = adm.delete(f"/api/admin/produtos/{produto_teste}")
            st2, l, _ = anonimo.get("/api/produtos")
            checar("produto desativado sai da vitrine", st == 204 and all(p["id"] != produto_teste for p in l), f"{st}")
            produto_teste = None
        # Status do pedido
        if cli.token:
            tam = escolher_tamanho(anonimo, 6)
            antes = saldo(anonimo, 6, tam)
            st, p, _ = cli.post("/api/pedidos", pedido(6, tam))
            if st == 201:
                pid = p["pedidoId"]
                pedidos_abertos.append((adm, pid))
                st, _, _ = adm.put(f"/api/admin/pedidos/{pid}/status", {"status": "Em Separação"})
                checar("admin muda o status para Em Separação", st == 204, f"{st}")
                st, r, _ = cli.post(f"/api/pedidos/{pid}/cancelar")
                checar("cliente não cancela depois da separação", st == 400, f"{st} {msg(r)}")
                st, _, _ = adm.put(f"/api/admin/pedidos/{pid}/status", {"status": "Pago"})
                checar("transição inválida (voltar para Pago) é recusada", st == 400, f"{st}")
                st, _, _ = adm.put(f"/api/admin/pedidos/{pid}/status", {"status": "Cancelado"})
                checar("admin cancela e o estoque volta", st == 204 and saldo(anonimo, 6, tam) == antes, f"{st}")
                pedidos_abertos.remove((adm, pid))
            else:
                checar("pedido para testar o status", False, f"{st} {msg(p)}")
    except (Pular, StopIteration, KeyError) as e:
        checar("seção interrompida", False, repr(e))

    # ------------------------------------------------------------ 5. moderação
    secao("Avaliações e moderação")
    try:
        if not (cli.token and adm.token):
            raise Pular("precisa do cliente e do admin")
        st, r, _ = outro.post("/api/produtos/19/avaliacoes", {"nota": 5, "comentario": "Ótima"})
        checar("quem não comprou não avalia", st == 400, f"{st} {msg(r)}")
        tam = escolher_tamanho(anonimo, 19)
        st, p, _ = cli.post("/api/pedidos", pedido(19, tam))
        if st != 201:
            raise Pular(f"pedido para avaliar: {st} {msg(p)}")
        pedidos_abertos.append((cli, p["pedidoId"]))
        comentario = f"Mais barato em www.outra-loja-{secrets.token_hex(2)}.com"
        st, r, _ = cli.post("/api/produtos/19/avaliacoes", {"nota": 4, "comentario": comentario})
        checar("comentário com link vai para moderação (Pendente)", st == 200 and r.get("status") == "Pendente", f"{st} {r}")
        st, pub, _ = anonimo.get("/api/produtos/19/avaliacoes")
        checar("pendente não aparece na loja", all(a.get("comentario") != comentario for a in pub))
        st, fila, _ = adm.get("/api/admin/avaliacoes?status=Pendente")
        av = next((a for a in fila if a["comentario"] == comentario), None)
        if not checar("admin vê a avaliação na fila", av is not None):
            raise Pular("avaliação não encontrada")
        st, _, _ = adm.put(f"/api/admin/avaliacoes/{av['id']}", {"status": "Publicada", "motivo": None})
        st2, pub, _ = anonimo.get("/api/produtos/19/avaliacoes")
        checar("publicada aparece na loja", st == 204 and any(a.get("comentario") == comentario for a in pub), f"{st}")
        st, _, _ = adm.put(f"/api/admin/avaliacoes/{av['id']}", {"status": "Oculta", "motivo": "Teste de aceitação: link externo"})
        st2, pub, _ = anonimo.get("/api/produtos/19/avaliacoes")
        checar("ocultada deixa de aparecer na loja", st == 204 and all(a.get("comentario") != comentario for a in pub), f"{st}")
        st, d, _ = anonimo.get("/api/produtos/19")
        checar("nota média ignora a avaliação oculta", st == 200)
    except Pular as e:
        checar("seção interrompida", False, str(e))

    # ------------------------------------------------------------ 6. limpeza de pedidos
    for dono, pid in list(pedidos_abertos):
        if dono is adm:
            adm.put(f"/api/admin/pedidos/{pid}/status", {"status": "Cancelado"})
        else:
            st, _, _ = dono.post(f"/api/pedidos/{pid}/cancelar")
            if st != 204 and adm.token:
                adm.put(f"/api/admin/pedidos/{pid}/status", {"status": "Cancelado"})
    if estoque_restaurar and adm.token:
        adm.put("/api/admin/estoque", dict(zip(("produtoId", "tamanho", "quantidade"), estoque_restaurar)))
    if produto_teste and adm.token:
        adm.delete(f"/api/admin/produtos/{produto_teste}")

    # ------------------------------------------------------------ 7. LGPD
    secao("LGPD: exportar dados e excluir conta")
    if cli.token:
        st, d, _ = cli.get("/api/auth/meus-dados")
        checar("exportação traz conta, pedidos e acessos",
               st == 200 and d["conta"]["email"] == email_cli and d["pedidos"] and "acessos" in d, f"{st}")
        end = (d.get("enderecos") or [{}])[0] if st == 200 else {}
        checar("endereço volta legível para o titular (cifrado só no banco)", end.get("rua") == ENDERECO["rua"], f"{end}")
        st, _, _ = cli.post("/api/auth/excluir-conta", {"senha": "errada"})
        checar("excluir conta exige a senha", st == 400, f"{st}")
    for c, email in ((cli, email_cli), (outro, email_outro)):
        if c.token:
            st, _, _ = c.post("/api/auth/excluir-conta", {"senha": SENHA})
            if c is cli:
                checar("conta excluída (204)", st == 204, f"{st}")
                st, _, _ = c.get("/api/auth/me")
                checar("token antigo deixa de valer na hora", st == 401, f"{st}")
                st, _ = Cliente(base).entrar(email, SENHA)
                checar("login da conta excluída é recusado", st == 401, f"{st}")
    if adm.token:
        st, d, _ = adm.get("/api/admin/acessos?limite=50")
        checar("painel mostra e-mail e IP mascarados", st == 200 and d and all("*" in a["email"] for a in d), f"{st}")

    return resumo()


def resumo() -> int:
    falhas = [r for r in resultados if not r[1]]
    print("\n" + "=" * 72)
    print(f"{len(resultados) - len(falhas)} de {len(resultados)} verificações OK")
    for nome, _, detalhe in falhas:
        print(f"  FALHOU  {nome}" + (f" — {detalhe}" if detalhe else ""))
    print("Confira o banco com Site/banco/conferencia.sql (estoque, totais, Joga Junto, auditoria).")
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
