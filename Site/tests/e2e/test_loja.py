#!/usr/bin/env python3
# ============================================================================
# JOGA BONITO — testes ponta a ponta (E2E) do site com Playwright
#
# Sobe a API simulada (mock-api.js, mesmo contrato da API .NET) na porta 5000,
# abre o Chromium sem janela e percorre a loja como um cliente e como o admin.
#
#   pip install playwright && python -m playwright install chromium
#   python Site/tests/e2e/test_loja.py            (ou: python -m unittest ...)
#
# Requisitos: Node.js 18+ e Python 3.10+. Nenhum banco ou SDK .NET é necessário.
# ============================================================================
import json
import os
import re
import socket
import subprocess
import sys
import time
import unittest
import urllib.request
from pathlib import Path

from playwright.sync_api import Page, expect, sync_playwright

SITE = Path(__file__).resolve().parents[2]
PORTA = 5000
BASE = f"http://localhost:{PORTA}"
PAGINAS = f"{BASE}/HTML/"

# Catálogo da planilha + trocas pedidas pelo grupo (ID, nome, preço) — a loja deve bater 100%
PLANILHA = [
    (1, "Camisa Brasil 2026 Home", 349.9), (2, "Camisa Argentina 2026 Home", 349.9),
    (3, "Camisa Portugal 2026 Home", 349.9), (4, "Camisa França 2026 Home", 349.9),
    (5, "Camisa Espanha 2026 Home", 329.9), (6, "Camisa Flamengo 2026 Home", 349.9),
    (7, "Camisa Corinthians 2026/27 Home", 349.9), (8, "Camisa Palmeiras 2026 Home", 349.9),
    (9, "Camisa Real Madrid 2026/27 Home", 399.9), (10, "Camisa Barcelona 2026/27 Home", 399.9),
    (11, "Camisa Al Nassr 2026/27 Home", 349.9), (12, "Camisa Boca Juniors 2026 Home", 329.9),
    (13, "Camisa Brasil 1994 Retrô", 299.9), (14, "Camisa Argentina 1986 Retrô", 299.9),
    (15, "Camisa Manchester United 2007/08", 329.9), (16, "Camisa Corinthians 2012 Retrô", 299.9),
    (17, "Camisa Barcelona 2005/06 Retrô", 329.9), (18, "Camisa Real Madrid 2001/02 Retrô", 329.9),
    (19, "Camisa Milan 2006/07", 329.9), (20, "Camisa Inter de Milão 2009/10", 299.9),
    (21, "Camisa Boca Juniors 2000 Retrô", 299.9), (22, "Camisa Santos 2011 Retrô", 329.9),
    (23, "Camisa Real Madrid 2017 Retrô", 329.9), (24, "Camisa Fiorentina 1998/99 Retrô", 299.9),
    (25, "Umbro Pro 5 Bump", 499.9), (26, "Joma Top Flex Rebound", 449.9),
    (27, "Nike Lunar Gato", 399.9), (28, "Umbro Adamant ProBump", 399.9),
    (29, "Nike Mercurial Vapor TF", 599.9), (30, "Nike Tiempo Legend TF", 549.9),
    (31, "adidas Predator TF", 499.9), (32, "adidas F50 TF", 499.9),
    (33, "Nike Mercurial Vapor FG", 899.9), (34, "Nike Phantom FG", 849.9),
    (35, "adidas Predator FG", 799.9), (36, "adidas F50 FG", 799.9),
]

_servidor = None
_pw = None
_navegador = None


def _porta_livre(porta: int) -> bool:
    with socket.socket() as s:
        return s.connect_ex(("127.0.0.1", porta)) != 0


def setUpModule():
    global _servidor, _pw, _navegador
    if not _porta_livre(PORTA):
        raise RuntimeError(f"A porta {PORTA} está ocupada. Pare a API/outro servidor antes de rodar os testes.")
    _servidor = subprocess.Popen(["node", str(SITE / "tests" / "e2e" / "mock-api.js"), str(SITE), str(PORTA)],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    for _ in range(50):
        if not _porta_livre(PORTA):
            break
        time.sleep(0.1)
    _pw = sync_playwright().start()
    _navegador = _pw.chromium.launch(headless=True)


def tearDownModule():
    if _navegador:
        _navegador.close()
    if _pw:
        _pw.stop()
    if _servidor:
        _servidor.terminate()
        _servidor.wait(5)


def api(caminho: str, metodo="GET", corpo=None, token=None, origem=None):
    req = urllib.request.Request(BASE + caminho, method=metodo,
                                 data=json.dumps(corpo).encode() if corpo is not None else None,
                                 headers={"Content-Type": "application/json",
                                          **({"Authorization": f"Bearer {token}"} if token else {}),
                                          **({"Origin": origem} if origem else {})})
    try:
        with urllib.request.urlopen(req) as r:
            texto = r.read().decode()
            return r.status, (json.loads(texto) if texto else None), dict(r.headers)
    except urllib.error.HTTPError as e:
        texto = e.read().decode()
        return e.code, (json.loads(texto) if texto else None), dict(e.headers)


class TesteLoja(unittest.TestCase):
    """Cada teste usa uma aba nova; erros de JavaScript e violações de CSP reprovam o teste."""

    def setUp(self):
        self.contexto = _navegador.new_context(viewport={"width": 1366, "height": 900}, locale="pt-BR")
        # Fontes do Google podem não carregar no CI: não interessam aos testes
        self.contexto.route(re.compile(r"https://(fonts\.|vlibras\.).*"), lambda rota: rota.abort())
        self.pagina: Page = self.contexto.new_page()
        self.erros: list[str] = []
        self.pagina.on("pageerror", lambda e: self.erros.append(f"JS: {e}"))
        self.pagina.on("console", lambda m: self.erros.append(f"CSP: {m.text}")
                       if m.type == "error" and "Content Security Policy" in m.text else None)
        self.pagina.on("dialog", lambda d: d.accept())

    def tearDown(self):
        self.contexto.close()
        self.assertEqual([e for e in self.erros if "VLibras" not in e], [], "Erros no navegador")

    def abrir(self, pagina: str):
        self.pagina.goto(PAGINAS + pagina)
        self.pagina.wait_for_load_state("networkidle")

    def entrar(self, email: str, senha: str):
        self.abrir("login.html")
        self.pagina.fill("#email", email)
        self.pagina.fill("#senha", senha)
        self.pagina.click("#btn-entrar")

    # ------------------------------------------------------------------ dados
    def test_01_catalogo_igual_a_planilha(self):
        status, produtos, _ = api("/api/produtos?ordem=nome")
        self.assertEqual(status, 200)
        obtido = sorted((p["id"], p["nome"], round(p["precoFinal"], 2)) for p in produtos)
        self.assertEqual(obtido, sorted(PLANILHA))
        chuteiras = [p for p in produtos if p["categoriaSlug"] == "chuteiras"]
        self.assertEqual(len(chuteiras), 12)
        self.assertTrue(all(p["marca"] in ("Nike", "adidas", "Umbro", "Joma") and p["solado"] for p in chuteiras))
        por_linha = {l: sum(p["linha"] == l for p in chuteiras) for l in ("Futsal", "Society", "Campo")}
        self.assertEqual(por_linha, {"Futsal": 4, "Society": 4, "Campo": 4})

    def test_02_imagens_existem_e_sem_froggy(self):
        _, produtos, _ = api("/api/produtos")
        for p in produtos:
            _, d, _ = api(f"/api/produtos/{p['id']}")
            for url in [p["img"], *d["imgs"]]:
                arquivo = SITE / url.replace("../", "")
                self.assertTrue(arquivo.is_file(), f"Imagem inexistente: {url} (produto {p['id']})")
        sobras = [f.name for f in (SITE / "IMG" / "Produtos").rglob("*") if "froggy" in f.name.lower()]
        self.assertEqual(sobras, [])

    def test_03_cabecalhos_de_seguranca(self):
        _, _, cab = api("/api/produtos")
        self.assertIn("default-src 'self'", cab.get("Content-Security-Policy", ""))
        self.assertEqual(cab.get("X-Content-Type-Options"), "nosniff")

    def test_04_sem_javascript_inline(self):
        """A CSP bloqueia onclick/onerror inline: nenhum arquivo do site pode usá-los."""
        padrao = re.compile(r"""\son[a-z]+\s*=\s*["']""", re.I)
        achados = [f"{f.name}:{n}" for pasta in ("HTML", "Javascript") for f in (SITE / pasta).iterdir()
                   if f.suffix in (".html", ".js") and f.name != "catalogo-local.js"
                   for n, linha in enumerate(f.read_text(encoding="utf-8").splitlines(), 1) if padrao.search(linha)]
        self.assertEqual(achados, [])
        scripts_inline = [f.name for f in (SITE / "HTML").glob("*.html")
                          if re.search(r"<script(?![^>]*\bsrc=)[^>]*>", f.read_text(encoding="utf-8"))]
        self.assertEqual(scripts_inline, [])

    # ----------------------------------------------------------------- vitrine
    def test_05_inicial_temporada_selecoes_e_clubes(self):
        self.abrir("inicial.html")
        grade = self.pagina.locator("#grade-temporada")
        expect(grade.locator(".card-produto")).to_have_count(5)            # 5 seleções
        expect(grade).to_contain_text("Camisa Espanha 2026 Home")
        self.pagina.click("#aba-clubes")
        expect(grade.locator(".card-produto")).to_have_count(6)            # limite da vitrine
        expect(grade).to_contain_text("Camisa Flamengo 2026 Home")
        expect(self.pagina.locator("#aba-clubes")).to_have_attribute("aria-selected", "true")
        expect(self.pagina.locator(".grade-retro .card-produto")).to_have_count(6)

    def test_06_catalogo_filtro_de_marca_so_em_chuteiras(self):
        self.abrir("catalogo.html?categoria=temporada-2026")
        expect(self.pagina.locator("#filtro-marca")).to_be_hidden()
        self.pagina.check("input[name=categoria][value=chuteiras]")
        expect(self.pagina.locator("#filtro-marca")).to_be_visible()
        expect(self.pagina.locator("#resultado .card-produto")).to_have_count(12)
        self.pagina.check("input[name=marca][value=Umbro]")
        cards = self.pagina.locator("#resultado .card-produto")
        expect(cards).to_have_count(2)                                     # Pro 5 Bump e Adamant ProBump
        for modelo in cards.locator(".card-modelo").all_text_contents():
            self.assertTrue(modelo.startswith("Umbro · "), modelo)
        self.assertIn("marca=Umbro", self.pagina.url)

    def test_07_produto_chuteira_mostra_marca_e_solado(self):
        self.abrir("Produtos.html?id=29")
        expect(self.pagina.locator("#produto-nome")).to_have_text("Nike Mercurial Vapor TF")
        ficha = self.pagina.locator(".produto-info .ficha")
        expect(ficha).to_contain_text("Nike")
        expect(ficha).to_contain_text("TF — society")
        expect(self.pagina.locator("#miniaturas img").first).to_be_visible()   # galeria com as fotos da pasta 29
        self.assertIn("IMG/Produtos/29/", self.pagina.locator("#miniaturas img").first.get_attribute("src"))
        expect(self.pagina.locator("#tamanhos button")).to_have_count(8)    # 37 a 44

    # ------------------------------------------------------------------ compra
    def test_08_compra_completa_com_cupom_e_pix(self):
        self.abrir("Produtos.html?id=13")
        self.pagina.click("#tamanhos button[data-tamanho='M']")
        self.pagina.click("#btn-adicionar")
        self.abrir("carrinho.html")
        self.pagina.click("#btn-finalizar")
        self.pagina.wait_for_url(re.compile(r"login\.html"))
        self.pagina.fill("#email", "matheus@estudante.com")
        self.pagina.fill("#senha", "Cliente@2026")
        self.pagina.click("#btn-entrar")
        self.pagina.wait_for_url(re.compile(r"/HTML/carrinho\.html"))
        self.pagina.fill("#cupom", "BEMVINDO10")
        self.pagina.click("#form-cupom button")
        expect(self.pagina.locator("#v-desconto")).to_contain_text("29,99")
        self.pagina.click("#btn-finalizar")
        for campo, valor in {"cep": "01310100", "numero": "1000", "rua": "Avenida Paulista",
                             "bairro": "Bela Vista", "cidade": "São Paulo", "uf": "SP"}.items():
            self.pagina.fill(f"#{campo}", valor)
        self.pagina.click("#etapa-1 button[type=submit]")
        self.pagina.click("#confirmar-pagamento")
        expect(self.pagina.locator("#sucesso-numero")).to_contain_text("1")
        self.abrir("pedidos.html")
        expect(self.pagina.locator("#lista-pedidos")).to_contain_text("Camisa Brasil 1994 Retrô")

    # --------------------------------------------------------------- segurança
    def test_09_bloqueio_apos_cinco_senhas_erradas(self):
        for _ in range(5):
            self.entrar("professor@unip.br", "senha-errada-1")
            expect(self.pagina.locator(".aviso:not([hidden])")).to_be_visible()
        expect(self.pagina.locator(".aviso:not([hidden])")).to_contain_text("bloqueada")
        self.entrar("professor@unip.br", "Unip@2026")                      # senha certa, mas bloqueada
        expect(self.pagina.locator(".aviso:not([hidden])")).to_contain_text("bloqueada")
        self.assertIn("login.html", self.pagina.url)

    def test_10_trocar_senha_exige_senha_atual(self):
        api("/api/auth/cadastro", "POST", {"nome": "Torcedor Teste", "email": "torcedor@teste.com",
                                            "senha": "Camisa10Gol", "aceiteLgpd": True})
        self.entrar("torcedor@teste.com", "Camisa10Gol")
        self.pagina.wait_for_url(re.compile(r"inicial\.html|pedidos\.html"))
        self.abrir("pedidos.html")
        self.pagina.click("#conta-senha summary")
        self.pagina.fill("#senha-atual", "errada123")
        self.pagina.fill("#senha-nova", "NovaSenha2027")
        self.pagina.fill("#senha-confirma", "NovaSenha2027")
        self.pagina.click("#form-senha button[type=submit]")
        expect(self.pagina.locator("#aviso-senha")).to_contain_text("senha atual não confere")
        self.pagina.fill("#senha-atual", "Camisa10Gol")
        self.pagina.click("#form-senha button[type=submit]")
        expect(self.pagina.locator(".toast")).to_contain_text("Senha alterada")
        status, _, _ = api("/api/auth/login", "POST", {"email": "torcedor@teste.com", "senha": "NovaSenha2027"})
        self.assertEqual(status, 200)
        # esta aba recebeu um token novo e continua logada
        self.abrir("pedidos.html")
        expect(self.pagina.locator("h1")).to_have_text("Meus pedidos")

    def test_13_trocar_senha_derruba_as_outras_sessoes(self):
        api("/api/auth/cadastro", "POST", {"nome": "Torcedor Dois", "email": "dois@teste.com",
                                            "senha": "Camisa10Gol", "aceiteLgpd": True})
        _, outro_aparelho, _ = api("/api/auth/login", "POST", {"email": "dois@teste.com", "senha": "Camisa10Gol"})
        _, este, _ = api("/api/auth/login", "POST", {"email": "dois@teste.com", "senha": "Camisa10Gol"})
        status, nova, _ = api("/api/auth/trocar-senha", "POST", {"senhaAtual": "Camisa10Gol", "novaSenha": "Outra2027"},
                              token=este["token"])
        self.assertEqual(status, 200)
        status, corpo, _ = api("/api/pedidos/meus", token=outro_aparelho["token"])
        self.assertEqual((status, corpo["mensagem"]), (401, "Sessão encerrada. Entre novamente."))
        self.assertEqual(api("/api/pedidos/meus", token=nova["token"])[0], 200)
        # "sair de todos" derruba inclusive o token novo
        self.assertEqual(api("/api/auth/sair-de-todos", "POST", token=nova["token"])[0], 204)
        self.assertEqual(api("/api/pedidos/meus", token=nova["token"])[0], 401)

    def test_14_login_e_cadastro_com_foto_de_jogador(self):
        for pagina, arquivo in (("login.html", "mbappe.jpg"), ("cadastro.html", "cr7-2008.jpg")):
            self.abrir(pagina)
            foto = self.pagina.locator(".auth-foto img")
            expect(foto).to_be_visible()
            self.assertIn(f"/IMG/Jogadores/{arquivo}", foto.get_attribute("src"))
            self.assertGreater(foto.evaluate("i => i.naturalWidth"), 0, f"{arquivo} não carregou")

    def test_11_admin_ve_log_de_acessos(self):
        api("/api/auth/login", "POST", {"email": "admin@jogabonito.com", "senha": "errada"})
        self.entrar("admin@jogabonito.com", "Admin@2026")
        self.pagina.wait_for_url(re.compile(r"admin\.html"))
        expect(self.pagina.locator("#status-conexoes")).to_contain_text("SQL Server")
        self.pagina.click("#tab-acessos")
        tabela = self.pagina.locator("#tabela-acessos")
        expect(tabela).to_contain_text("ad***@jogabonito.com")      # e-mail mascarado no painel
        self.assertNotIn("admin@jogabonito.com", tabela.inner_text())
        expect(tabela).to_contain_text("Senha incorreta")
        expect(tabela).to_contain_text("Sucesso")

    def test_12_celular_sem_rolagem_horizontal(self):
        self.pagina.set_viewport_size({"width": 390, "height": 844})
        for pagina in ("inicial.html", "catalogo.html", "Produtos.html?id=33", "carrinho.html", "login.html"):
            self.abrir(pagina)
            largura = self.pagina.evaluate("document.documentElement.scrollWidth")
            self.assertLessEqual(largura, 390, f"{pagina} rola na horizontal ({largura}px)")

    # ------------------------------------------------- moderação de avaliações
    def comprar_pela_api(self, email, senha, produto_id, tamanho):
        _, sessao, _ = api("/api/auth/login", "POST", {"email": email, "senha": senha})
        status, _, _ = api("/api/pedidos", "POST", {"itens": [{"produtoId": produto_id, "tamanho": tamanho, "quantidade": 1}],
                                                    "formaPagamento": "PIX", "parcelas": 1, "origem": "Web"}, token=sessao["token"])
        self.assertEqual(status, 201)

    def test_15_avaliacao_com_link_vai_para_moderacao(self):
        api("/api/auth/cadastro", "POST", {"nome": "Torcedor Tres", "email": "tres@teste.com", "senha": "Camisa10Gol", "aceiteLgpd": True})
        self.comprar_pela_api("tres@teste.com", "Camisa10Gol", 8, "M")
        self.entrar("tres@teste.com", "Camisa10Gol")
        self.pagina.wait_for_url(re.compile(r"inicial\.html"))
        self.abrir("Produtos.html?id=8")
        self.pagina.click("label[for=n5]")
        self.pagina.fill("#comentario", "Achei mais barato em www.outraloja.com")
        self.pagina.click("#form-avaliacao button[type=submit]")
        expect(self.pagina.locator(".toast").last).to_contain_text("revisada")
        expect(self.pagina.locator("#lista-avaliacoes")).not_to_contain_text("outraloja")

        # Admin publica pela aba Avaliações e a avaliação aparece na loja
        self.pagina.evaluate("localStorage.clear()")
        self.entrar("admin@jogabonito.com", "Admin@2026")
        self.pagina.wait_for_url(re.compile(r"admin\.html"))
        expect(self.pagina.locator("#contador-pendentes")).to_have_text("1")
        self.pagina.click("#tab-avaliacoes")
        card = self.pagina.locator(".moderacao", has_text="outraloja")
        card.locator("[data-moderar=Oculta]").click()                       # sem motivo: recusado
        expect(self.pagina.locator(".toast").last).to_contain_text("motivo")
        card.locator("[data-moderar=Publicada]").click()
        expect(self.pagina.locator(".toast").last).to_contain_text("publicada")
        self.abrir("Produtos.html?id=8")
        expect(self.pagina.locator("#lista-avaliacoes")).to_contain_text("outraloja")

    # ----------------------------------------------------------- LGPD no site
    def test_16_baixar_dados_e_excluir_conta(self):
        api("/api/auth/cadastro", "POST", {"nome": "Torcedor Quatro", "email": "quatro@teste.com", "senha": "Camisa10Gol", "aceiteLgpd": True})
        self.entrar("quatro@teste.com", "Camisa10Gol")
        self.pagina.wait_for_url(re.compile(r"inicial\.html"))
        self.abrir("pedidos.html#conta-dados")
        with self.pagina.expect_download() as baixado:
            self.pagina.click("#baixar-dados")
        conteudo = json.loads(Path(baixado.value.path()).read_text(encoding="utf-8"))
        self.assertEqual(conteudo["conta"]["email"], "quatro@teste.com")

        self.pagina.fill("#senha-exclusao", "errada")
        self.pagina.click("#form-excluir button[type=submit]")
        expect(self.pagina.locator("#aviso-exclusao")).to_contain_text("Senha incorreta")
        self.pagina.fill("#senha-exclusao", "Camisa10Gol")
        self.pagina.click("#form-excluir button[type=submit]")
        self.pagina.wait_for_url(re.compile(r"inicial\.html\?conta=excluida"))
        expect(self.pagina.locator(".toast").last).to_contain_text("excluída")
        self.assertEqual(api("/api/auth/login", "POST", {"email": "quatro@teste.com", "senha": "Camisa10Gol"})[0], 401)

    # ------------------------------------------------- checkout e Joga Junto
    def test_17_checkout_simulado_joga_junto_e_carrinho_preservado_na_falha(self):
        self.abrir("Produtos.html?id=10")
        self.pagina.click("#tamanhos button[data-tamanho='M']")
        self.pagina.click("#btn-adicionar")
        self.entrar("matheus@estudante.com", "Cliente@2026")
        self.abrir("carrinho.html")
        expect(self.pagina.locator("#v-joga-junto")).to_contain_text("4,00")      # 1% de R$ 399,90
        self.pagina.click("#btn-finalizar")
        for campo, valor in {"cep": "01310100", "numero": "1", "rua": "Rua A", "bairro": "Centro",
                             "cidade": "São Paulo", "uf": "SP"}.items():
            self.pagina.fill(f"#{campo}", valor)
        self.pagina.click("#etapa-1 button[type=submit]")
        expect(self.pagina.locator(".aviso-simulado")).to_contain_text("Pagamento simulado")

        # Outro cliente compra a última peça antes da confirmação: o servidor recusa
        _, admin, _ = api("/api/auth/login", "POST", {"email": "admin@jogabonito.com", "senha": "Admin@2026"})
        api("/api/admin/estoque", "PUT", {"produtoId": 10, "tamanho": "M", "quantidade": 0}, token=admin["token"])
        self.pagina.click("#confirmar-pagamento")
        expect(self.pagina.locator("#aviso-etapa-2")).to_contain_text("esgotado")
        expect(self.pagina.locator("#etapa-3")).to_be_hidden()
        itens = self.pagina.evaluate("JB.carrinho.itens().length")
        self.assertEqual(itens, 1, "o carrinho não pode ser apagado quando a compra falha")

    # --------------------------------------------------------- acessibilidade
    def test_18_teclado_pular_conteudo_e_abas_do_admin(self):
        self.abrir("inicial.html")
        self.pagina.keyboard.press("Tab")
        expect(self.pagina.locator(":focus")).to_have_text("Pular para o conteúdo")
        self.pagina.keyboard.press("Enter")
        self.assertIn("#conteudo", self.pagina.url)

        self.entrar("admin@jogabonito.com", "Admin@2026")
        self.pagina.wait_for_url(re.compile(r"admin\.html"))
        self.pagina.focus("#tab-visao")
        self.pagina.keyboard.press("ArrowRight")
        expect(self.pagina.locator("#tab-pedidos")).to_be_focused()
        expect(self.pagina.locator("#aba-pedidos")).to_be_visible()
        self.pagina.keyboard.press("End")
        expect(self.pagina.locator("#tab-acessos")).to_have_attribute("aria-selected", "true")
        # VLibras também no painel administrativo
        self.assertEqual(self.pagina.locator("div[vw]").count(), 1)

    def test_19_todos_os_campos_tem_rotulo_e_imagens_tem_alt(self):
        sem_nome = """() => [...document.querySelectorAll('input:not([type=hidden]), select, textarea')]
            .filter(c => !(c.getAttribute('aria-label') || c.getAttribute('aria-labelledby') || c.closest('label')
                           || (c.id && document.querySelector(`label[for="${c.id}"]`))))
            .map(c => c.id || c.name || c.outerHTML.slice(0, 60))"""
        sem_alt = "() => [...document.images].filter(i => !i.hasAttribute('alt')).map(i => i.src)"
        self.entrar("admin@jogabonito.com", "Admin@2026")
        self.pagina.wait_for_url(re.compile(r"admin\.html"))
        paginas = ["inicial.html", "catalogo.html", "Produtos.html?id=1", "carrinho.html", "pedidos.html",
                   "privacidade.html", "admin.html"]
        for pagina in paginas:
            self.abrir(pagina)
            self.assertEqual(self.pagina.evaluate(sem_nome), [], f"campos sem rótulo em {pagina}")
            self.assertEqual(self.pagina.evaluate(sem_alt), [], f"imagens sem alt em {pagina}")
        self.pagina.evaluate("localStorage.clear()")
        for pagina in ("login.html", "cadastro.html"):
            self.abrir(pagina)
            self.assertEqual(self.pagina.evaluate(sem_nome), [], f"campos sem rótulo em {pagina}")

    def test_20_fonte_ampliada_nao_esconde_a_compra(self):
        self.pagina.set_viewport_size({"width": 390, "height": 844})
        self.abrir("Produtos.html?id=33")
        for _ in range(4):   # no celular a barra fica no menu; o clique é o mesmo
            self.pagina.evaluate("document.querySelector(\"[aria-label='Aumentar fonte']\").click()")
        self.assertGreater(self.pagina.evaluate("parseFloat(getComputedStyle(document.documentElement).fontSize)"), 16)
        self.pagina.click("#tamanhos button:not([disabled])")
        botao = self.pagina.locator("#btn-adicionar")
        botao.scroll_into_view_if_needed()
        expect(botao).to_be_visible()
        expect(botao).to_be_enabled()
        largura = self.pagina.evaluate("document.documentElement.scrollWidth")
        self.assertLessEqual(largura, 390, "fonte ampliada criou rolagem horizontal")
        botao.click()
        self.assertEqual(self.pagina.evaluate("JB.carrinho.itens().length"), 1)

    # ------------------------------------------------ endereço da API publicado
    def test_21_site_publicado_usa_a_propria_origem(self):
        """Num domínio de verdade o site nunca chama o localhost do visitante."""
        outro = subprocess.Popen(["node", str(SITE / "tests" / "e2e" / "mock-api.js"), str(SITE), "5100"],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
        try:
            for _ in range(50):
                if not _porta_livre(5100):
                    break
                time.sleep(0.1)
            navegador = _pw.chromium.launch(headless=True, args=["--host-resolver-rules=MAP loja.jogabonito.test 127.0.0.1"])
            try:
                pagina = navegador.new_page()
                chamadas = []
                pagina.on("request", lambda r: chamadas.append(r.url) if "/api/" in r.url else None)
                pagina.goto("http://loja.jogabonito.test:5100/HTML/catalogo.html")
                pagina.wait_for_load_state("networkidle")
                self.assertEqual(pagina.evaluate("JB.API_BASE"), "")
                expect(pagina.locator("#resultado .card-produto")).to_have_count(36)
                self.assertTrue(chamadas and all(u.startswith("http://loja.jogabonito.test:5100/api/") for u in chamadas), chamadas)
            finally:
                navegador.close()
        finally:
            outro.terminate()
            outro.wait(5)

    # ------------------------------------------------------- segurança da sessão
    def test_22_token_fica_fora_do_alcance_do_javascript(self):
        """Sessão do site em cookie HttpOnly: um XSS não consegue ler nem levar o token."""
        self.entrar("matheus@estudante.com", "Cliente@2026")
        self.pagina.wait_for_url(re.compile(r"inicial\.html"))
        armazenado = self.pagina.evaluate("JSON.stringify(Object.assign({}, localStorage))")
        self.assertNotIn("tok-", armazenado)
        self.assertNotIn("jb_token", armazenado)
        self.assertNotIn("jb_sessao", self.pagina.evaluate("document.cookie"))
        cookie = next(c for c in self.contexto.cookies() if c["name"] == "jb_sessao")
        self.assertTrue(cookie["httpOnly"])
        self.assertEqual(cookie["sameSite"], "Strict")
        # mesmo sem token visível, a sessão funciona
        self.assertEqual(self.pagina.evaluate("JB.api('/api/auth/me', {autenticado: true}).then(u => u.email)"),
                         "matheus@estudante.com")
        # sair apaga o cookie no servidor
        self.pagina.evaluate("JB.sessao.sair(false)")
        self.pagina.wait_for_timeout(300)
        self.assertFalse(any(c["name"] == "jb_sessao" and c["value"] for c in self.contexto.cookies()))

    def test_23_csrf_escrita_sem_cabecalho_do_site_e_recusada(self):
        self.entrar("matheus@estudante.com", "Cliente@2026")
        self.pagina.wait_for_url(re.compile(r"inicial\.html"))
        # Como faria uma página maliciosa: POST com o cookie, mas sem o cabeçalho X-JB-Requisicao
        status = self.pagina.evaluate("""fetch('/api/auth/sair-de-todos', {method: 'POST', credentials: 'include'})
                                          .then(r => r.status)""")
        self.assertEqual(status, 403)
        self.assertEqual(self.pagina.evaluate("JB.api('/api/auth/me', {autenticado: true}).then(u => u.id)"), 2,
                         "a sessão continua válida: o ataque não teve efeito")
        st, _, _ = api("/api/auth/sair", "POST")
        self.assertEqual(st, 204)
        st, corpo, _ = api("/api/auth/login", "POST", {"email": "x@y.com", "senha": "a"}, origem="https://golpe.example")
        self.assertEqual(st, 403, "origem de outro site é recusada")

    def test_24_senha_comum_ou_com_o_email_e_recusada(self):
        for senha, trecho in (("senha123", "comum"), ("Brasil2026", "comum"), ("joaquim2026x", "e-mail")):
            st, corpo, _ = api("/api/auth/cadastro", "POST", {"nome": "Joaquim Silva", "email": "joaquim@teste.com",
                                                              "senha": senha, "aceiteLgpd": True})
            self.assertEqual(st, 400, senha)
            self.assertIn(trecho, corpo["mensagem"])

    def test_25_loja_reconecta_sozinha_quando_a_api_volta(self):
        """API fora do ar: vitrine do catálogo salvo + aviso; API de volta: a página se atualiza sozinha."""
        bloqueio = re.compile(r".*/(api|health)/.*")
        self.contexto.route(bloqueio, lambda rota: rota.abort())
        self.pagina.goto(PAGINAS + "inicial.html")
        aviso = self.pagina.locator(".aviso-offline")
        expect(aviso).to_be_visible()
        expect(aviso).to_contain_text("Reconectando")
        expect(self.pagina.locator(".card-produto").first).to_be_visible()   # catálogo salvo
        self.contexto.unroute(bloqueio)
        self.pagina.wait_for_load_state("load")
        expect(self.pagina.locator(".aviso-offline")).to_have_count(0, timeout=15000)
        self.assertFalse(self.pagina.evaluate("!!JB.modoOffline"), "depois de reconectar, os dados vêm da API")

    # --------------------------------------------------------- design: craques e ficha
    def test_26_craques_ficha_completa_e_frete_por_cep(self):
        # Camisas só com o time; os jogadores ficam na seção de craques
        status, produtos, _ = api("/api/produtos")
        jogadores = re.compile(r"CR7|Cristiano|Ronaldinho|Zidane|Kak[áa]|Neymar|Messi|Batistuta|Romário|Mbapp|Lamine", re.I)
        self.assertEqual([p["nome"] for p in produtos if jogadores.search(p["nome"] + " " + p["descricao"])], [])

        self.abrir("inicial.html")
        mini = self.pagina.locator("#craques-lista .craque-mini")
        expect(mini).to_have_count(5)
        for nome in ("Romário", "Kaká", "Cristiano Ronaldo", "Kylian Mbappé", "Lamine Yamal"):
            expect(self.pagina.locator("#craques-lista")).to_contain_text(nome)
        expect(self.pagina.locator("#craques-lista")).not_to_contain_text("Messi")

        self.abrir("craques.html")
        cards = self.pagina.locator("#craques-completa .craque")
        expect(cards).to_have_count(5)
        cr7 = cards.filter(has_text="Cristiano Ronaldo")
        self.assertIn("Produtos.html?id=15", cr7.locator("a.craque-produto").get_attribute("href"))
        foto = cr7.locator("img.craque-foto")
        foto.scroll_into_view_if_needed()
        foto.evaluate("i => i.complete && i.naturalWidth ? 1 : new Promise(r => i.addEventListener('load', r, {once: true}))")
        self.assertGreater(foto.evaluate("i => i.naturalWidth"), 0)
        # Todos os craques têm foto em IMG/Jogadores
        for foto in cards.locator("img.craque-foto").all():
            foto.scroll_into_view_if_needed()
            foto.evaluate("i => i.complete ? 1 : new Promise(r => { i.addEventListener('load', r, {once: true}); i.addEventListener('error', r, {once: true}); })")
            self.assertGreater(foto.evaluate("i => i.naturalWidth"), 0, foto.get_attribute("src"))
        self.assertIn("Produtos.html?id=19", cards.filter(has_text="Kaká").locator("a.craque-produto").get_attribute("href"))
        # Se a foto sumir da pasta, o craque aparece num cartão com número e cores do time
        self.pagina.route("**/IMG/Jogadores/kaka.jpg", lambda rota: rota.abort())
        self.abrir("craques.html")
        kaka = self.pagina.locator("#craques-completa .craque").filter(has_text="Kaká")
        kaka.scroll_into_view_if_needed()
        expect(kaka.locator(".craque-cartao")).to_contain_text("22")
        self.pagina.unroute("**/IMG/Jogadores/kaka.jpg")

        self.abrir("Produtos.html?id=15")
        expect(self.pagina.locator("#produto-nome")).to_have_text("Camisa Manchester United 2007/08")
        expect(self.pagina.locator("#em-campo")).to_contain_text("Manchester United")
        expect(self.pagina.locator("#em-campo")).not_to_contain_text("Cristiano")
        abas = self.pagina.locator(".abas-ficha [role=tab]")
        expect(abas).to_have_count(4)
        abas.first.focus()
        self.pagina.keyboard.press("ArrowRight")
        expect(self.pagina.locator("#aba-ficha-medidas")).to_have_attribute("aria-selected", "true")
        expect(self.pagina.locator("#painel-ficha-medidas table")).to_be_visible()
        self.pagina.fill("#cep-frete", "01310100")
        self.pagina.click("#form-frete button")
        expect(self.pagina.locator("#frete-resultado")).to_contain_text("Frete grátis")
        expect(self.pagina.locator("#frete-resultado")).to_contain_text("dias úteis")

        self.abrir("Produtos.html?id=13")                       # retrô sem jogador: história da camisa
        expect(self.pagina.locator("#em-campo")).to_contain_text("tetra")
        self.abrir("catalogo.html?categoria=temporada-2026")
        expect(self.pagina.locator("#catalogo-craque")).to_contain_text("Mbappé")

    # ------------------------------------------------- login sem "erro de conexão"
    def test_27_live_server_vai_para_a_api_e_o_login_fica(self):
        """Live Server abre em 127.0.0.1:5500; o login tem que valer nas páginas seguintes."""
        live = subprocess.Popen([sys.executable, "-m", "http.server", "5500", "--bind", "127.0.0.1",
                                 "--directory", str(SITE.parent)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for _ in range(50):
                if not _porta_livre(5500):
                    break
                time.sleep(0.1)
            self.pagina.goto("http://127.0.0.1:5500/Site/HTML/login.html?volta=pedidos.html")
            self.pagina.wait_for_url(re.compile(r"127\.0\.0\.1:5000/HTML/login\.html\?volta=pedidos\.html"))
            self.pagina.wait_for_load_state("networkidle")
            self.pagina.click("#contas-demo [data-email='matheus@estudante.com']")
            self.pagina.wait_for_url(re.compile(r"/HTML/pedidos\.html"))
            self.pagina.wait_for_load_state("networkidle")
            self.assertTrue(self.pagina.evaluate("JB.sessao.logado()"))
            self.abrir_em("http://127.0.0.1:5000/HTML/inicial.html")
            self.assertTrue(self.pagina.evaluate("JB.api('/api/auth/me', {autenticado: true}).then(u => !!u.id)"))
        finally:
            live.terminate()
            live.wait(5)

    def abrir_em(self, url):
        self.pagina.goto(url)
        self.pagina.wait_for_load_state("networkidle")

    def test_28_login_espera_a_api_ligar_em_vez_de_dar_erro(self):
        bloqueio = re.compile(r".*/(api|health)/.*")
        self.abrir("login.html")
        self.contexto.route(bloqueio, lambda rota: rota.abort())        # API "desligada"
        self.pagina.fill("#email", "matheus@estudante.com")
        self.pagina.fill("#senha", "Cliente@2026")
        self.pagina.click("#btn-entrar")
        expect(self.pagina.locator("#aviso")).to_contain_text("Ligando a loja")
        self.pagina.wait_for_timeout(2000)
        self.contexto.unroute(bloqueio)                                  # API "ligou"
        self.pagina.wait_for_url(re.compile(r"inicial\.html"), timeout=20000)
        self.assertTrue(self.pagina.evaluate("JB.sessao.logado()"))

    def test_29_contas_de_demonstracao_entram_com_um_clique(self):
        self.abrir("login.html")
        expect(self.pagina.locator("#contas-demo")).to_be_visible()
        self.pagina.click("#contas-demo [data-email='admin@jogabonito.com']")
        self.pagina.wait_for_url(re.compile(r"admin\.html"))

    # ------------------------------------------------------------ site público
    def test_30_site_publico_funciona_sem_servidor(self):
        """publico/ (GitHub Pages/Vercel): link raiz → inicial, login, compra e pedido, sem API nenhuma."""
        subprocess.run([sys.executable, str(SITE / "ferramentas" / "publicar_estatico.py"),
                        str(SITE.parent / "publico")], check=True, stdout=subprocess.DEVNULL)
        estatico = subprocess.Popen([sys.executable, "-m", "http.server", "5600", "--bind", "127.0.0.1",
                                     "--directory", str(SITE.parent / "publico")],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for _ in range(50):
                if not _porta_livre(5600):
                    break
                time.sleep(0.1)
            fora = []
            self.pagina.on("request", lambda r: fora.append(r.url) if ":5000" in r.url else None)
            p = self.pagina
            p.goto("http://127.0.0.1:5600/")
            p.wait_for_url(re.compile(r"/HTML/inicial\.html$"))
            p.wait_for_load_state("networkidle")
            expect(p.locator(".faixa-demo")).to_be_visible()
            expect(p.locator(".aviso-offline")).to_have_count(0)
            expect(p.locator("#craques-lista .craque-mini")).to_have_count(5)

            p.goto("http://127.0.0.1:5600/HTML/Produtos.html?id=13")
            p.wait_for_load_state("networkidle")
            p.click("#tamanhos button[data-tamanho='M']")
            p.click("#btn-adicionar")
            p.goto("http://127.0.0.1:5600/HTML/carrinho.html")
            p.wait_for_load_state("networkidle")
            p.click("#btn-finalizar")
            p.wait_for_url(re.compile(r"login\.html"))
            p.click("#contas-demo [data-email='matheus@estudante.com']")
            p.wait_for_url(re.compile(r"/HTML/carrinho\.html"))
            p.wait_for_load_state("networkidle")
            p.click("#btn-finalizar")
            for campo, valor in {"cep": "01310100", "numero": "1000", "rua": "Avenida Paulista",
                                 "bairro": "Bela Vista", "cidade": "São Paulo", "uf": "SP"}.items():
                p.fill(f"#{campo}", valor)
            p.click("#etapa-1 button[type=submit]")
            p.click("#confirmar-pagamento")
            expect(p.locator("#sucesso-numero")).to_contain_text("#")
            p.goto("http://127.0.0.1:5600/HTML/pedidos.html")              # outra página: dados continuam
            p.wait_for_load_state("networkidle")
            expect(p.locator("#lista-pedidos")).to_contain_text("Camisa Brasil 1994 Retrô")

            p.evaluate("JB.sessao.sair(false)")
            p.goto("http://127.0.0.1:5600/HTML/login.html")
            p.click("#contas-demo [data-email='admin@jogabonito.com']")
            p.wait_for_url(re.compile(r"admin\.html"))
            p.wait_for_load_state("networkidle")
            expect(p.locator("#kpis")).to_contain_text("A despachar")
            self.assertFalse(p.locator("#link-swagger").is_visible())
            self.assertEqual(fora, [], "o site público não pode depender da API local")
        finally:
            estatico.terminate()
            estatico.wait(5)


if __name__ == "__main__":
    unittest.main(verbosity=2)
