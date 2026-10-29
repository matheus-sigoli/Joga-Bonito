#!/usr/bin/env python3
# ============================================================================
# JOGA BONITO — gera o SITE PÚBLICO (pasta publico/) para GitHub Pages ou Vercel
#
#   python3 Site/ferramentas/gerar_catalogo.py      # organiza as fotos e o catálogo (opcional)
#   python3 Site/ferramentas/publicar_estatico.py   # cria publico/
#
# O site público não depende de servidor nem de banco: com JB_CONFIG.modo = "demo",
# o motor Javascript/loja-demo.js responde a API dentro do navegador do visitante
# (mesmas regras da API .NET; dados guardados só no navegador dele). Quem abre o link
# cai direto na página inicial e pode entrar com as contas de demonstração, criar conta,
# comprar, acompanhar pedidos e usar o painel do administrador.
#
# Só a biblioteca padrão do Python (roda no build da Vercel e no GitHub Actions).
# ============================================================================
from __future__ import annotations

import json
import os
import re
import shutil
import stat
import sys
from pathlib import Path

SITE = Path(__file__).resolve().parent.parent
RAIZ = SITE.parent
SAIDA = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else RAIZ / "publico"

# A mesma política de conteúdo da API (CabecalhosSegurancaMiddleware.cs). No GitHub Pages
# não há como enviar cabeçalhos, então ela vai também numa <meta> em cada página.
CSP = ("default-src 'self'; "
       "script-src 'self' https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/ 'unsafe-eval' 'wasm-unsafe-eval'; "
       "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/; "
       "font-src 'self' data: https://fonts.gstatic.com https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/; "
       "img-src 'self' data: blob: https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/; "
       "media-src 'self' blob: https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/; "
       "connect-src 'self' https://viacep.com.br https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/; "
       "worker-src 'self' blob:; frame-src 'self' https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/; "
       "object-src 'none'; base-uri 'self'; form-action 'self'")

REDIRECIONA = """<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Joga Bonito — camisas e chuteiras de futebol</title>
  <meta name="description" content="Joga Bonito: camisas da Temporada 2026, camisas retrô e chuteiras de campo, society e futsal. Projeto PIM IV — UNIP 2026/2.">
  <meta http-equiv="refresh" content="0; url=HTML/inicial.html">
  <link rel="icon" href="IMG/jogabonito.ico">
  <link rel="canonical" href="HTML/inicial.html">
  <script src="redireciona.js"></script>
</head>
<body style="background:#07110B;color:#F3F6F1;font-family:system-ui,sans-serif">
  <p><a href="HTML/inicial.html" style="color:#FCCA0F">Abrir a loja Joga Bonito</a></p>
</body>
</html>
"""


def produtos_do_catalogo() -> list[dict]:
    js = (SITE / "Javascript" / "catalogo-local.js").read_text(encoding="utf-8")
    inicio = js.index("[", js.index("JB_CATALOGO_LOCAL"))
    dados, _ = json.JSONDecoder().raw_decode(js[inicio:])
    return dados


def _liberar_e_repetir(funcao, caminho, _erro) -> None:
    # No Windows o rmtree não apaga itens somente-leitura, e o copytree leva esse atributo
    # das pastas de Site/IMG (comum em pastas do OneDrive) para a saída da execução anterior
    os.chmod(caminho, stat.S_IWRITE)
    funcao(caminho)


def apagar_pasta(pasta: Path) -> None:
    if sys.version_info >= (3, 12):
        shutil.rmtree(pasta, onexc=_liberar_e_repetir)
    else:
        shutil.rmtree(pasta, onerror=_liberar_e_repetir)


def main() -> None:
    if SAIDA.exists():
        apagar_pasta(SAIDA)
    SAIDA.mkdir(parents=True)

    for pasta in ("HTML", "CSS", "Javascript", "IMG"):
        shutil.copytree(SITE / pasta, SAIDA / pasta,
                        ignore=shutil.ignore_patterns("_originais", "Thumbs.db", ".DS_Store", "__*"))

    # Modo demonstração + produtos para o motor da loja (páginas sem catalogo-local.js também precisam)
    (SAIDA / "Javascript" / "config.js").write_text(
        "// Site público: a loja roda inteira no navegador (Javascript/loja-demo.js), sem servidor.\n"
        "window.JB_CONFIG = { apiBase: null, modo: \"demo\" };\n", encoding="utf-8")
    produtos = produtos_do_catalogo()
    (SAIDA / "Javascript" / "demo-produtos.js").write_text(
        "// Gerado por ferramentas/publicar_estatico.py a partir de catalogo-local.js\n"
        "window.JB_DEMO_PRODUTOS = " + json.dumps(produtos, ensure_ascii=False) + ";\n", encoding="utf-8")

    # Em cada página: CSP em <meta> e o motor logo depois do config.js (antes de qualquer chamada à API)
    paginas = sorted((SAIDA / "HTML").glob("*.html"))
    for pagina in paginas:
        html = pagina.read_text(encoding="utf-8")
        alvo = '<script src="../Javascript/config.js"></script>'
        if alvo not in html:
            raise SystemExit(f"{pagina.name}: não encontrei {alvo}")
        html = html.replace(alvo, alvo + '\n  <script src="../Javascript/demo-produtos.js"></script>'
                                         '\n  <script src="../Javascript/loja-demo.js"></script>', 1)
        if "Content-Security-Policy" not in html:
            html = re.sub(r'(<meta charset="[^"]*">)',
                          lambda m: m.group(1) + f'\n  <meta http-equiv="Content-Security-Policy" content="{CSP}">', html, count=1)
        pagina.write_text(html, encoding="utf-8")

    # Entrada do site: quem abre o link cai na página inicial
    (SAIDA / "index.html").write_text(REDIRECIONA, encoding="utf-8")
    (SAIDA / "redireciona.js").write_text('location.replace("HTML/inicial.html" + location.search + location.hash);\n',
                                          encoding="utf-8")
    (SAIDA / "404.html").write_text(REDIRECIONA, encoding="utf-8")
    (SAIDA / ".nojekyll").write_text("", encoding="utf-8")        # GitHub Pages: servir pastas como estão

    total = sum(1 for _ in SAIDA.rglob("*") if _.is_file())
    tamanho = sum(f.stat().st_size for f in SAIDA.rglob("*") if f.is_file()) / 1_048_576
    print(f"Site público em {SAIDA}: {len(paginas)} páginas, {len(produtos)} produtos, {total} arquivos ({tamanho:.1f} MB).")
    print("Abra publico/index.html por um servidor (ex.: python -m http.server -d publico) ou publique no GitHub Pages/Vercel.")


if __name__ == "__main__":
    main()
