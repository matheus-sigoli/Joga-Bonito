#!/usr/bin/env python3
# ============================================================================
# JOGA BONITO — gerador do catálogo (fonte única dos 36 produtos da planilha)
#
# Uso:  python3 Site/ferramentas/gerar_catalogo.py
#
# Gera, a partir da lista CATALOGO abaixo:
#   1. IMG/Produtos/<id>/ilustracao.svg   — imagem desenhada de cada produto
#      (camisa nas cores da equipe; chuteira com a sola do piso). Usada como
#      capa quando o produto não tem foto real na pasta.
#   2. O bloco de PRODUTOS e GALERIA do banco/seed.sql (entre os marcadores
#      "-- <catalogo>" e "-- </catalogo>").
#   3. Javascript/catalogo-local.js — vitrine offline quando a API está fora.
#
# Fotos reais: coloque as fotos em IMG/Produtos/<id>/ com qualquer nome e formato
# (jpg, png, webp, avif...). Elas viram 1.jpg, 2.jpg... (originais guardados em
# IMG/Produtos/_originais/), a primeira é a capa e a ilustração sai. Sem fotos, a capa
# é a ilustração. Os dados dos produtos vêm do catalogo-local.js (edições preservadas).
# ============================================================================
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from xml.sax.saxutils import escape

RAIZ = Path(__file__).resolve().parent.parent          # pasta Site/
PASTA_IMG = RAIZ / "IMG" / "Produtos"
SEED = RAIZ / "banco" / "seed.sql"
LOCAL_JS = RAIZ / "Javascript" / "catalogo-local.js"

# ----------------------------------------------------------------------------
# Catálogo (planilha catalogo_de_produtos.xlsx). Cores das camisas:
#   base, detalhe (gola/punho/número) e padrão: liso | listras | aros | faixa | central
# ----------------------------------------------------------------------------
TEMP, RETRO, CHUT = "temporada-2026", "retro", "chuteiras"

CATALOGO = [
    # id, categoria, nome, linha, equipe, ano, preço, destaque, desenho, descrição
    (1, TEMP, "Camisa Brasil 2026 Home", "Seleção", "Brasil", 2026, 349.90, True,
     dict(base="#F7D117", detalhe="#0B7A3B", padrao="liso", numero="26"),
     "A amarelinha da temporada 2026: base canarinho, gola e punhos em verde e tecido leve de secagem rápida. Escudo bordado e modelagem regular."),
    (2, TEMP, "Camisa Argentina 2026 Home", "Seleção", "Argentina", 2026, 349.90, False,
     dict(base="#FFFFFF", faixa="#75AADB", detalhe="#1B2A4A", padrao="listras", numero="26"),
     "As listras alvicelestes da campeã do mundo em versão 2026, com detalhes em azul-marinho e tecido respirável."),
    (3, TEMP, "Camisa Portugal 2026 Home", "Seleção", "Portugal", 2026, 349.90, False,
     dict(base="#C8102E", detalhe="#0B6B3A", padrao="liso", numero="26", num="#F2EFE6"),
     "O vermelho da seleção portuguesa com acabamentos em verde, gola careca e tecido de alta ventilação."),
    (4, TEMP, "Camisa França 2026 Home", "Seleção", "França", 2026, 349.90, False,
     dict(base="#1B2A4A", detalhe="#E4002B", padrao="liso", numero="26"),
     "O azul-marinho dos Bleus com detalhes em vermelho e branco. Tecido leve e caimento moderno."),
    (5, TEMP, "Camisa Espanha 2026 Home", "Seleção", "Espanha", 2026, 329.90, False,
     dict(base="#C60B1E", detalhe="#1B2A4A", padrao="liso", numero="26", num="#FFC400"),
     "O vermelho da Fúria em versão 2026, com mangas em azul-marinho e detalhes em amarelo. Tecido leve e respirável."),
    (6, TEMP, "Camisa Flamengo 2026 Home", "Clube", "Flamengo", 2026, 349.90, True,
     dict(base="#C8102E", faixa="#111111", detalhe="#FFFFFF", padrao="aros", numero="26"),
     "O manto rubro-negro de listras horizontais da temporada 2026, com tecido de secagem rápida e escudo bordado."),
    (7, TEMP, "Camisa Corinthians 2026/27 Home", "Clube", "Corinthians", 2026, 349.90, True,
     dict(base="#F4F4F2", detalhe="#111111", padrao="liso", numero="26"),
     "O manto alvinegro 2026/27: base branca, detalhes em preto e tecido de alta respirabilidade."),
    (8, TEMP, "Camisa Palmeiras 2026 Home", "Clube", "Palmeiras", 2026, 349.90, False,
     dict(base="#006437", detalhe="#FFFFFF", padrao="liso", numero="26"),
     "O verde alviverde da temporada 2026 com detalhes em branco, gola careca e tecido leve."),
    (9, TEMP, "Camisa Real Madrid 2026/27 Home", "Clube", "Real Madrid", 2026, 399.90, True,
     dict(base="#F7F7F5", detalhe="#C9A227", padrao="liso", numero="26"),
     "O branco merengue 2026/27 com acabamentos em dourado e tecido com controle de suor. Escudo termoaplicado."),
    (10, TEMP, "Camisa Barcelona 2026/27 Home", "Clube", "Barcelona", 2026, 399.90, False,
     dict(base="#A50044", faixa="#004D98", detalhe="#EDBB00", padrao="listras", numero="26"),
     "As listras azul-grená do Barça 2026/27 com detalhes dourados e tecido de secagem rápida."),
    (11, TEMP, "Camisa Al Nassr 2026/27 Home", "Clube", "Al Nassr", 2026, 349.90, False,
     dict(base="#FFD100", detalhe="#1A3C8E", padrao="liso", numero="26"),
     "O amarelo do Al Nassr com detalhes em azul, gola careca e tecido leve de alta ventilação."),
    (12, TEMP, "Camisa Boca Juniors 2026 Home", "Clube", "Boca Juniors", 2026, 329.90, False,
     dict(base="#0A3A82", faixa="#F3B229", detalhe="#F3B229", padrao="faixa", numero="26"),
     "O azul e ouro de La Bombonera com a faixa horizontal clássica, em versão 2026."),

    (13, RETRO, "Camisa Brasil 1994 Retrô", "Seleção", "Brasil", 1994, 299.90, True,
     dict(base="#F7D117", detalhe="#0B7A3B", padrao="liso", numero="94"),
     "Réplica retrô da amarelinha do tetracampeonato nos Estados Unidos, com gola verde e corte da época."),
    (14, RETRO, "Camisa Argentina 1986 Retrô", "Seleção", "Argentina", 1986, 299.90, False,
     dict(base="#FFFFFF", faixa="#75AADB", detalhe="#1B2A4A", padrao="listras", numero="86"),
     "Réplica retrô da alviceleste campeã no México em 1986, com listras verticais e escudo vintage."),
    (15, RETRO, "Camisa Manchester United 2007/08", "Clube", "Manchester United", 2008, 329.90, False,
     dict(base="#DA020E", detalhe="#FFFFFF", padrao="liso", numero="08"),
     "Réplica retrô do vermelho de Old Trafford na temporada 2007/08, a do título inglês e da Champions League conquistada em Moscou."),
    (16, RETRO, "Camisa Corinthians 2012 Retrô", "Clube", "Corinthians", 2012, 299.90, False,
     dict(base="#F4F4F2", detalhe="#111111", padrao="liso", numero="12"),
     "Réplica retrô do manto alvinegro de 2012, ano da Libertadores e do Mundial de Clubes."),
    (17, RETRO, "Camisa Barcelona 2005/06 Retrô", "Clube", "Barcelona", 2006, 329.90, False,
     dict(base="#A50044", faixa="#004D98", detalhe="#EDBB00", padrao="listras", numero="06"),
     "Réplica retrô do Barça 2005/06, campeão espanhol e europeu, com as listras azul-grená da época."),
    (18, RETRO, "Camisa Real Madrid 2001/02 Retrô", "Clube", "Real Madrid", 2002, 329.90, False,
     dict(base="#F7F7F5", detalhe="#3B2D6B", padrao="liso", numero="02"),
     "Réplica retrô do branco do centenário merengue, a temporada da nona Champions League, conquistada em Glasgow."),
    (19, RETRO, "Camisa Milan 2006/07", "Clube", "AC Milan", 2007, 329.90, True,
     dict(base="#E30613", faixa="#111111", detalhe="#FFFFFF", padrao="listras", numero="07"),
     "Réplica retrô do rossonero de listras vermelhas e pretas da temporada 2006/07, campeã europeia em Atenas."),
    (20, RETRO, "Camisa Inter de Milão 2009/10", "Clube", "Inter de Milão", 2010, 299.90, False,
     dict(base="#0068A8", faixa="#111111", detalhe="#C9A227", padrao="listras", numero="10"),
     "Réplica retrô do nerazzurro da tríplice coroa de 2009/10, com listras azuis e pretas."),
    (21, RETRO, "Camisa Boca Juniors 2000 Retrô", "Clube", "Boca Juniors", 2000, 299.90, False,
     dict(base="#0A3A82", faixa="#F3B229", detalhe="#F3B229", padrao="faixa", numero="00"),
     "Réplica retrô do Boca de 2000, campeão da Libertadores e do Intercontinental, com a faixa amarela no peito."),
    (22, RETRO, "Camisa Santos 2011 Retrô", "Clube", "Santos", 2011, 329.90, True,
     dict(base="#F4F4F2", detalhe="#111111", padrao="liso", numero="11"),
     "Réplica retrô do manto branco do Santos de 2011, tricampeão da Libertadores."),
    (23, RETRO, "Camisa Real Madrid 2017 Retrô", "Clube", "Real Madrid", 2017, 329.90, True,
     dict(base="#F7F7F5", detalhe="#1B2A4A", padrao="liso", numero="17"),
     "Réplica retrô do branco merengue da temporada 2016/17, campeã espanhola e bicampeã europeia seguida."),
    (24, RETRO, "Camisa Fiorentina 1998/99 Retrô", "Clube", "Fiorentina", 1999, 299.90, False,
     dict(base="#5B2A86", detalhe="#F4F4F2", padrao="liso", numero="99"),
     "Réplica retrô do roxo da Fiorentina 1998/99, a Viola que brigou pelo título italiano."),

    (25, CHUT, "Umbro Pro 5 Bump", "Futsal", "Umbro", "IC — quadra", 499.90, True,
     dict(cabedal="#151515", detalhe="#6B4FD8", sola="#5B3FBF", tipo="IC"), ""),
    (26, CHUT, "Joma Top Flex Rebound", "Futsal", "Joma", "Indoor — quadra", 449.90, False,
     dict(cabedal="#F2EFE6", detalhe="#C9A227", sola="#C9A227", tipo="IC"), ""),
    (27, CHUT, "Nike Lunar Gato", "Futsal", "Nike", "IC — quadra", 399.90, False,
     dict(cabedal="#F2EFE6", detalhe="#E8505B", sola="#F4A28C", tipo="IC"), ""),
    (28, CHUT, "Umbro Adamant ProBump", "Futsal", "Umbro", "IC — quadra", 399.90, False,
     dict(cabedal="#2A2A2A", detalhe="#9A9A9A", sola="#E0B23A", tipo="IC"), ""),
    (29, CHUT, "Nike Mercurial Vapor TF", "Society", "Nike", "TF — society", 599.90, True,
     dict(cabedal="#C8F31D", detalhe="#151515", sola="#9A9A9A", tipo="TF"), ""),
    (30, CHUT, "Nike Tiempo Legend TF", "Society", "Nike", "TF — society", 549.90, False,
     dict(cabedal="#F2EFE6", detalhe="#151515", sola="#9A9A9A", tipo="TF"), ""),
    (31, CHUT, "adidas Predator TF", "Society", "adidas", "TF — society", 499.90, False,
     dict(cabedal="#151515", detalhe="#D7263D", sola="#9A9A9A", tipo="TF"), ""),
    (32, CHUT, "adidas F50 TF", "Society", "adidas", "TF — society", 499.90, False,
     dict(cabedal="#1E5AA8", detalhe="#F2EFE6", sola="#9A9A9A", tipo="TF"), ""),
    (33, CHUT, "Nike Mercurial Vapor FG", "Campo", "Nike", "FG — campo", 899.90, True,
     dict(cabedal="#FF6A13", detalhe="#151515", sola="#F2EFE6", tipo="FG"), ""),
    (34, CHUT, "Nike Phantom FG", "Campo", "Nike", "FG — campo", 849.90, False,
     dict(cabedal="#151515", detalhe="#FCCA0F", sola="#FCCA0F", tipo="FG"), ""),
    (35, CHUT, "adidas Predator FG", "Campo", "adidas", "FG — campo", 799.90, False,
     dict(cabedal="#D7263D", detalhe="#F2EFE6", sola="#F2EFE6", tipo="FG"), ""),
    (36, CHUT, "adidas F50 FG", "Campo", "adidas", "FG — campo", 799.90, False,
     dict(cabedal="#F5E14B", detalhe="#151515", sola="#F2EFE6", tipo="FG"), ""),
]

DESC_SOLA = {
    "IC": "Sola lisa de borracha que não marca o piso, com ponto de giro no antepé. Para quadra, salão e parquet.",
    "TF": "Solado com dezenas de travas baixas de borracha que espalham o peso. Para grama sintética (society e fut7).",
    "FG": "Travas altas para gramado natural firme, com tração na arrancada e na frenagem. Não use em grama sintética.",
}
MODELO_SOLA = {"IC": "Futsal · Quadra", "TF": "Society · Grama sintética", "FG": "Campo · Grama natural"}
NOME_CATEGORIA = {TEMP: ("Temporada 2026", 1), RETRO: ("Camisas Retrô", 2), CHUT: ("Chuteiras", 3)}

FUNDO = "#16211A"
TEXTO = "#F2EFE6"
FONTE = "'Bebas Neue', Impact, 'Arial Narrow', sans-serif"


# ------------------------------- Ilustrações --------------------------------
CAMISA = ("M250 170 L330 150 Q400 205 470 150 L550 170 L700 275 L640 395 L585 355 "
          "L588 865 Q400 885 212 865 L215 355 L160 395 L100 275 Z")


def svg_camisa(p) -> str:
    id_, _, nome, _, equipe, ano, *_ = p
    d = p[8]
    base, det = d["base"], d["detalhe"]
    faixa = d.get("faixa", det)
    padrao = []
    if d["padrao"] == "listras":
        for i, x in enumerate(range(100, 700, 60)):
            if i % 2:
                padrao.append(f'<rect x="{x}" y="120" width="60" height="780" fill="{faixa}"/>')
    elif d["padrao"] == "aros":
        for i, y in enumerate(range(150, 900, 64)):
            if i % 2:
                padrao.append(f'<rect x="90" y="{y}" width="620" height="64" fill="{faixa}"/>')
    elif d["padrao"] == "faixa":
        padrao.append(f'<rect x="90" y="430" width="620" height="130" fill="{faixa}"/>')
    elif d["padrao"] == "central":
        padrao.append(f'<rect x="320" y="120" width="160" height="780" fill="{faixa}"/>')
    # cor do número contrasta com o que estiver atrás dele
    atras = faixa if d["padrao"] in ("faixa", "central") else base
    num_cor = d.get("num") or (det if det.lower() != atras.lower() else TEXTO)
    legenda = f"{equipe} · {ano}".upper()
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 800" role="img" aria-label="{escape(nome)}">
  <title>{escape(nome)}</title>
  <rect width="800" height="800" fill="{FUNDO}"/>
  <defs><clipPath id="c{id_}"><path d="{CAMISA}"/></clipPath></defs>
  <g transform="translate(80 30) scale(.8)">
  <g clip-path="url(#c{id_})">
    <rect x="80" y="120" width="640" height="800" fill="{base}"/>
    {"".join(padrao)}
    <path d="M100 275 L160 395 L180 380 L122 262 Z M700 275 L640 395 L620 380 L678 262 Z" fill="{det}"/>
    <rect x="80" y="845" width="640" height="40" fill="{det}" opacity=".9"/>
  </g>
  <path d="M330 150 Q400 205 470 150" fill="none" stroke="{det}" stroke-width="22" stroke-linecap="round"/>
  <path d="{CAMISA}" fill="none" stroke="#000" stroke-opacity=".25" stroke-width="3"/>
  <text x="400" y="640" text-anchor="middle" font-family="{FONTE}" font-size="230" fill="{num_cor}">{escape(d["numero"])}</text>
  </g>
  <text x="400" y="768" text-anchor="middle" font-family="{FONTE}" font-size="40" letter-spacing="4" fill="{TEXTO}" fill-opacity=".75">{escape(legenda)}</text>
</svg>
'''


SOLA = ("M150 780 C150 712 300 700 430 706 C575 712 690 712 690 780 "
        "C690 848 575 850 430 854 C300 860 150 848 150 780 Z")
CABEDAL = ("M175 470 C175 420 220 395 270 398 C320 400 340 430 380 452 C450 490 560 515 640 540 "
           "C690 556 712 590 700 615 L170 615 C160 560 165 510 175 470 Z")


def svg_chuteira(p) -> str:
    id_, _, nome, linha, marca, solado, *_ = p
    d = p[8]
    cab, det, sola, tipo = d["cabedal"], d["detalhe"], d["sola"], d["tipo"]
    # vista lateral: travas embaixo da sola
    travas_lado, travas_baixo = [], []
    if tipo == "FG":
        for x in (215, 265, 470, 545, 615, 665):
            travas_lado.append(f'<path d="M{x-14} 640 L{x-8} 678 L{x+8} 678 L{x+14} 640 Z" fill="{sola}"/>')
        for cx, cy in ((215, 750), (215, 810), (265, 780), (470, 735), (470, 825), (550, 745), (550, 815), (625, 760), (625, 800), (665, 780)):
            travas_baixo.append(f'<circle cx="{cx}" cy="{cy}" r="17" fill="{sola}" stroke="#000" stroke-opacity=".3" stroke-width="3"/>')
    elif tipo == "TF":
        for x in range(190, 690, 26):
            travas_lado.append(f'<rect x="{x}" y="640" width="12" height="16" rx="3" fill="{sola}"/>')
        for x in range(175, 690, 30):
            for y in range(722, 850, 30):
                travas_baixo.append(f'<circle cx="{x}" cy="{y}" r="8" fill="{sola}"/>')
    else:  # IC: sola lisa de borracha, ponto de giro e frisos
        escuro = 'stroke="#000" stroke-opacity=".35"'
        travas_baixo.append(f'<circle cx="560" cy="780" r="44" fill="none" {escuro} stroke-width="9"/>')
        travas_baixo.append(f'<circle cx="560" cy="780" r="20" fill="none" {escuro} stroke-width="6"/>')
        for x in range(190, 480, 34):
            travas_baixo.append(f'<path d="M{x} 728 l18 104" {escuro} stroke-width="6" stroke-linecap="round"/>')
        for x in range(620, 680, 22):
            travas_baixo.append(f'<path d="M{x} 742 l0 76" {escuro} stroke-width="6" stroke-linecap="round"/>')
    cadarcos = "".join(f'<path d="M{x} {y} l34 -22" stroke="{det}" stroke-width="7" stroke-linecap="round"/>'
                       for x, y in ((360, 470), (405, 492), (450, 510), (495, 526)))
    # IC: a sola inteira é a borracha; TF/FG: placa escura com as travas na cor da sola
    placa = sola if tipo == "IC" else "#2A2A2A"
    legenda = f"{marca} · {solado}".upper()
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 800" role="img" aria-label="{escape(nome)}">
  <title>{escape(nome)}</title>
  <rect width="800" height="800" fill="{FUNDO}"/>
  <text x="400" y="160" text-anchor="middle" font-family="{FONTE}" font-size="150" fill="{TEXTO}" fill-opacity=".08">{escape(linha.upper())}</text>
  <g transform="translate(0 -190)">
  <g>
    {"".join(travas_lado)}
    <rect x="160" y="612" width="550" height="30" rx="14" fill="{placa}"/>
    <path d="{CABEDAL}" fill="{cab}" stroke="#000" stroke-opacity=".25" stroke-width="3"/>
    <path d="M230 600 C330 520 470 520 640 560" fill="none" stroke="{det}" stroke-width="16" stroke-linecap="round"/>
    <path d="M178 470 C200 430 240 410 275 412" fill="none" stroke="{det}" stroke-width="10" stroke-linecap="round"/>
    {cadarcos}
  </g>
  <path d="{SOLA}" fill="{placa}"/>
  {"".join(travas_baixo)}
  </g>
  <text x="400" y="768" text-anchor="middle" font-family="{FONTE}" font-size="40" letter-spacing="4" fill="{TEXTO}" fill-opacity=".75">{escape(legenda)}</text>
</svg>
'''


# ------------------------------- Fotos reais --------------------------------
# Basta colocar as fotos em IMG/Produtos/<id>/ — com qualquer nome e formato.
# Elas são organizadas como 1.jpg, 2.jpg... (ordem natural dos nomes: "frente", "2", "10"...),
# reduzidas para no máximo 1200 px e salvas em JPEG; os arquivos originais vão para
# IMG/Produtos/_originais/<id>/ (nada é apagado). Sem o Pillow instalado, as fotos são usadas
# como estão. A primeira foto vira a capa; com fotos, a ilustração SVG deixa de existir.
EXT_FOTO = {".jpg", ".jpeg", ".png", ".webp", ".avif", ".gif", ".jfif", ".bmp"}
PASTA_ORIGINAIS = PASTA_IMG / "_originais"
LADO_MAXIMO = 1200
BYTES_MAXIMO = 400 * 1024


def _ordem_natural(f: Path):
    return [(0, int(t), "") if t.isdigit() else (1, 0, t) for t in re.split(r"(\d+)", f.stem.lower()) if t]


def _arquivos_de_foto(pasta: Path) -> list[Path]:
    if not pasta.is_dir():
        return []
    return sorted((f for f in pasta.iterdir() if f.is_file() and f.suffix.lower() in EXT_FOTO
                   and not f.name.startswith("__")), key=_ordem_natural)


def organizar_fotos(id_: int) -> list[Path]:
    """Normaliza as fotos da pasta do produto e devolve a lista final, na ordem da galeria."""
    pasta = PASTA_IMG / str(id_)
    arqs = _arquivos_de_foto(pasta)
    if not arqs:
        return []
    try:
        from PIL import Image, ImageOps
    except ImportError:
        return arqs                                         # sem Pillow: usa como estão

    def pronta(i, f):
        if f.name != f"{i}.jpg":
            return False
        if f.stat().st_size > BYTES_MAXIMO:              # arquivo pesado: recomprime (o site carrega mais rápido)
            return False
        try:
            with Image.open(f) as im:
                return max(im.size) <= LADO_MAXIMO
        except OSError:
            return False

    if all(pronta(i, f) for i, f in enumerate(arqs, 1)):
        return arqs                                         # já organizadas: nada a fazer

    convertidas, mantidas = [], []
    for f in arqs:
        destino = pasta / f"__nova{len(convertidas) + 1}.jpg"
        try:
            with Image.open(f) as im:
                im = ImageOps.exif_transpose(im)
                if im.mode in ("RGBA", "LA", "P"):
                    im = im.convert("RGBA")
                    fundo = Image.new("RGB", im.size, (255, 255, 255))
                    fundo.paste(im, mask=im.split()[-1])
                    im = fundo
                else:
                    im = im.convert("RGB")
                im.thumbnail((LADO_MAXIMO, LADO_MAXIMO))
                for qualidade in (85, 78, 70, 62):           # até caber em BYTES_MAXIMO
                    im.save(destino, "JPEG", quality=qualidade, optimize=True, progressive=True)
                    if destino.stat().st_size <= BYTES_MAXIMO:
                        break
            convertidas.append((f, destino))
        except OSError as erro:
            print(f"  aviso: produto {id_}: não consegui abrir {f.name} ({erro}); a foto fica como está")
            mantidas.append(f)

    guarda = PASTA_ORIGINAIS / str(id_)
    guarda.mkdir(parents=True, exist_ok=True)
    for original, _ in convertidas:
        alvo = guarda / original.name
        n = 1
        while alvo.exists():
            alvo = guarda / f"{original.stem}-{n}{original.suffix}"
            n += 1
        original.replace(alvo)
    finais = []
    for i, (_, nova) in enumerate(convertidas, 1):
        final = pasta / f"{i}.jpg"
        nova.replace(final)
        finais.append(final)
    if convertidas:
        print(f"  produto {id_}: {len(convertidas)} foto(s) organizada(s) (originais em IMG/Produtos/_originais/{id_}/)")
    return finais + mantidas


def fotos(id_: int) -> list[str]:
    return [f"../IMG/Produtos/{id_}/{f.name}" for f in organizar_fotos(id_)]


# --------------------------- Dados editados à mão ---------------------------
# catalogo-local.js é a fonte dos dados dos produtos (nome, preço, descrição, destaque...):
# quem edita esse arquivo não perde nada quando este script roda. A lista CATALOGO acima
# fornece só as cores das ilustrações e serve de ponto de partida para produtos novos.
def carregar_local() -> dict[int, dict]:
    if not LOCAL_JS.exists():
        return {}
    js = LOCAL_JS.read_text(encoding="utf-8")
    inicio = js.find("[", js.find("JB_CATALOGO_LOCAL"))
    if inicio < 0:
        return {}
    try:
        dados, _ = json.JSONDecoder().raw_decode(js[inicio:])
    except ValueError as erro:
        print(f"aviso: catalogo-local.js com erro de sintaxe ({erro}); usando a lista do gerador")
        return {}
    return {int(p["id"]): p for p in dados if isinstance(p, dict) and str(p.get("id", "")).isdigit()}


# ------------------------------- Estoque (igual ao seed) ---------------------
def estoque(id_: int, chuteira: bool) -> list[dict]:
    tams = [str(t) for t in range(37, 45)] if chuteira else ["P", "M", "G", "GG", "XG"]
    out = []
    for ordem, t in enumerate(tams, 1):
        if (id_ + ordem) % 9 == 0:
            q = 0
        elif (id_ + ordem) % 7 == 0:
            q = 3
        else:
            q = 8 + ((id_ * 7 + ordem * 5) % 22)
        out.append({"tamanho": t, "quantidade": q})
    return out


def sql_txt(v) -> str:
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "1" if v else "0"
    if isinstance(v, (int, float)):
        return f"{v:.2f}" if isinstance(v, float) else str(v)
    return "'" + str(v).replace("'", "''") + "'"


def produtos_novos(local: dict[int, dict]) -> list[tuple]:
    """Produtos que existem só no catalogo-local.js (IDs novos): entram com uma ilustração neutra."""
    conhecidos = {p[0] for p in CATALOGO}
    novos = []
    for id_, d in sorted(local.items()):
        if id_ in conhecidos:
            continue
        cat = d.get("categoriaSlug") if d.get("categoriaSlug") in (TEMP, RETRO, CHUT) else RETRO
        if cat == CHUT:
            tipo = {"Futsal": "IC", "Society": "TF"}.get(d.get("linha"), "FG")
            desenho = dict(cabedal="#16733A", detalhe="#F2EFE6", sola="#F2EFE6", tipo=tipo)
            novos.append((id_, cat, d.get("nome", f"Produto {id_}"), d.get("linha", "Campo"), d.get("marca") or "",
                          d.get("solado") or "", float(d.get("preco", 1)), bool(d.get("destaque")), desenho, d.get("descricao", "")))
        else:
            desenho = dict(base="#16733A", detalhe="#F2EFE6", padrao="liso", numero=str(d.get("ano") or "")[-2:] or "10")
            novos.append((id_, cat, d.get("nome", f"Produto {id_}"), d.get("linha", "Clube"), d.get("equipe") or "",
                          d.get("ano"), float(d.get("preco", 1)), bool(d.get("destaque")), desenho, d.get("descricao", "")))
    return novos


def main() -> None:
    linhas_sql, galeria_sql, locais = [], [], []
    local = carregar_local()
    for p in CATALOGO + produtos_novos(local):
        id_, cat, nome, linha, equipe_ou_marca, ano_ou_solado, preco, destaque, desenho, desc = p
        chuteira = cat == CHUT
        pasta = PASTA_IMG / str(id_)
        pasta.mkdir(parents=True, exist_ok=True)

        lista_fotos = fotos(id_)
        svg = pasta / "ilustracao.svg"
        if lista_fotos:
            svg.unlink(missing_ok=True)                 # com foto real, a ilustração sai de cena
        else:
            svg.write_text(svg_chuteira(p) if chuteira else svg_camisa(p), encoding="utf-8")
        imgs = lista_fotos or [f"../IMG/Produtos/{id_}/ilustracao.svg"]
        capa = imgs[0]
        if chuteira:
            marca, solado, equipe, ano = equipe_ou_marca, ano_ou_solado, None, None
            modelo = MODELO_SOLA[desenho["tipo"]]
            desc = f"{nome}: {DESC_SOLA[desenho['tipo']]} Numeração 37 a 44."
        else:
            marca, solado, equipe, ano = None, None, equipe_ou_marca, ano_ou_solado
            modelo = "Torcedor · Temporada 2026" if cat == TEMP else "Coleção Retrô"

        # O que foi editado no catalogo-local.js vale mais que a lista do gerador
        ed = local.get(id_, {})
        nome = ed.get("nome") or nome
        linha = ed.get("linha") or linha
        modelo = ed.get("modelo") or modelo
        desc = ed.get("descricao") or desc
        preco = float(ed["preco"]) if isinstance(ed.get("preco"), (int, float)) and ed["preco"] > 0 else preco
        destaque = bool(ed["destaque"]) if "destaque" in ed else destaque
        promo = ed.get("precoPromocional")
        promo = float(promo) if isinstance(promo, (int, float)) and 0 < promo < preco else None
        if chuteira:
            marca = ed.get("marca") or marca
            solado = ed.get("solado") or solado
        else:
            equipe = ed.get("equipe") or equipe
            ano = ed.get("ano") if isinstance(ed.get("ano"), int) else ano
        var = {TEMP: "@Temp", RETRO: "@Retro", CHUT: "@Chut"}[cat]
        linhas_sql.append(
            f"    ({id_}, {var}, {sql_txt(nome)}, {sql_txt(modelo)}, {sql_txt(linha)}, {sql_txt(equipe)}, "
            f"{sql_txt(ano)}, {sql_txt(marca)}, {sql_txt(solado)}, {sql_txt(desc)}, {preco:.2f}, {f"{promo:.2f}" if promo else "NULL"}, "
            f"{sql_txt(capa)}, {sql_txt(destaque)})")
        for ordem, url in enumerate(imgs, 1):
            galeria_sql.append(f"({id_}, {sql_txt(url)}, {ordem})")
        cat_nome, cat_id = NOME_CATEGORIA[cat]
        tams = estoque(id_, chuteira)
        locais.append({
            "id": id_, "nome": nome, "modelo": modelo, "linha": linha, "equipe": equipe, "ano": ano,
            "marca": marca, "solado": solado, "descricao": desc, "preco": preco, "precoPromocional": promo,
            "precoFinal": promo or preco, "img": capa, "destaque": destaque, "categoriaId": cat_id,
            "categoria": cat_nome, "categoriaSlug": cat, "estoque": sum(t["quantidade"] for t in tams),
            "notaMedia": 0, "totalAvaliacoes": 0, "imgs": imgs, "tamanhos": tams,
        })

    # Versão do catálogo: muda sempre que nome, preço, imagens etc. mudarem neste arquivo.
    # O seed compara com a versão gravada no banco e, se for diferente, atualiza os produtos
    # existentes — sem precisar apagar o banco (os pedidos e clientes são preservados).
    versao = hashlib.sha1("\n".join(linhas_sql + galeria_sql).encode("utf-8")).hexdigest()[:12]

    bloco = f"""-- <catalogo>  (gerado por ferramentas/gerar_catalogo.py — não edite à mão)
-- ----------------------------------------------------------------------------
-- 2. PRODUTOS E GALERIA — 36 itens: 12 Temporada 2026 · 12 Retrô · 12 Chuteiras
--    Carga INCREMENTAL e versionada:
--      * produtos que faltam são inseridos (banco novo ou banco antigo com menos itens);
--      * se a versão do catálogo mudou, os produtos 1-36 recebem nome, preço, imagens etc.
--        novos e a galeria é refeita; se não mudou, nada é alterado (edições do painel ficam);
--      * a versão fica numa propriedade estendida da tabela Produtos (CatalogoVersao).
-- ----------------------------------------------------------------------------
SET XACT_ABORT ON;
DECLARE @VersaoCatalogo NVARCHAR(20) = N'{versao}';
DECLARE @VersaoAtual NVARCHAR(20) = (
    SELECT CAST(value AS NVARCHAR(20)) FROM sys.extended_properties
    WHERE major_id = OBJECT_ID('dbo.Produtos') AND minor_id = 0 AND name = 'CatalogoVersao');
DECLARE @Temp INT  = (SELECT Id FROM dbo.Categorias WHERE Slug = 'temporada-2026');
DECLARE @Retro INT = (SELECT Id FROM dbo.Categorias WHERE Slug = 'retro');
DECLARE @Chut INT  = (SELECT Id FROM dbo.Categorias WHERE Slug = 'chuteiras');

DECLARE @Catalogo TABLE (
    Id INT PRIMARY KEY, CategoriaId INT, Nome VARCHAR(100), Modelo VARCHAR(100), Linha VARCHAR(20),
    Equipe VARCHAR(60), Ano SMALLINT, Marca VARCHAR(40), Solado VARCHAR(40), Descricao VARCHAR(1000),
    Preco DECIMAL(10,2), PrecoPromocional DECIMAL(10,2), Imagem VARCHAR(200), Destaque BIT);
INSERT INTO @Catalogo VALUES
{(","+chr(10)).join(linhas_sql)};

DECLARE @Galeria TABLE (ProdutoId INT, Url VARCHAR(300), Ordem INT);
INSERT INTO @Galeria VALUES
    {(","+chr(10)+"    ").join(galeria_sql)};

BEGIN TRANSACTION;
    -- (a) insere os produtos que ainda não existem, mantendo os IDs da planilha
    SET IDENTITY_INSERT dbo.Produtos ON;
    INSERT INTO dbo.Produtos (Id, CategoriaId, Nome, Modelo, Linha, Equipe, Ano, Marca, Solado, Descricao,
                              Preco, PrecoPromocional, Imagem, Destaque)
    SELECT C.Id, C.CategoriaId, C.Nome, C.Modelo, C.Linha, C.Equipe, C.Ano, C.Marca, C.Solado, C.Descricao,
           C.Preco, C.PrecoPromocional, C.Imagem, C.Destaque
    FROM @Catalogo C
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Produtos P WHERE P.Id = C.Id);
    SET IDENTITY_INSERT dbo.Produtos OFF;

    -- (b) catálogo novo: atualiza os produtos existentes, refaz a galeria e
    --     remove tamanhos que não pertencem mais ao tipo do produto (camisa x chuteira)
    IF ISNULL(@VersaoAtual, N'') <> @VersaoCatalogo
    BEGIN
        UPDATE P SET
            CategoriaId = C.CategoriaId, Nome = C.Nome, Modelo = C.Modelo, Linha = C.Linha, Equipe = C.Equipe,
            Ano = C.Ano, Marca = C.Marca, Solado = C.Solado, Descricao = C.Descricao, Preco = C.Preco,
            PrecoPromocional = C.PrecoPromocional, Imagem = C.Imagem, Destaque = C.Destaque, Ativo = 1,
            AtualizadoEm = SYSDATETIME()
        FROM dbo.Produtos P INNER JOIN @Catalogo C ON C.Id = P.Id;

        DELETE FROM dbo.ProdutoImagens WHERE ProdutoId IN (SELECT Id FROM @Catalogo);
        INSERT INTO dbo.ProdutoImagens (ProdutoId, Url, Ordem) SELECT ProdutoId, Url, Ordem FROM @Galeria;

        DELETE E FROM dbo.Estoque E
        INNER JOIN @Catalogo C ON C.Id = E.ProdutoId
        WHERE (C.CategoriaId = @Chut AND E.Tamanho NOT IN ('37','38','39','40','41','42','43','44'))
           OR (C.CategoriaId <> @Chut AND E.Tamanho NOT IN ('P','M','G','GG','XG'));

        IF @VersaoAtual IS NULL
            EXEC sys.sp_addextendedproperty @name = N'CatalogoVersao', @value = @VersaoCatalogo,
                 @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'Produtos';
        ELSE
            EXEC sys.sp_updateextendedproperty @name = N'CatalogoVersao', @value = @VersaoCatalogo,
                 @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'Produtos';
    END
COMMIT TRANSACTION;
GO
-- </catalogo>"""
    seed = SEED.read_text(encoding="utf-8")
    seed, n = re.subn(r"-- <catalogo>.*?-- </catalogo>", lambda _: bloco, seed, flags=re.S)
    if n != 1:
        raise SystemExit("Marcadores -- <catalogo> / -- </catalogo> não encontrados em seed.sql")
    SEED.write_text(seed, encoding="utf-8")

    js = LOCAL_JS.read_text(encoding="utf-8")
    inicio = js.index("const JB_CATALOGO_LOCAL = [")
    fim = js.index("\n];", inicio) + 3
    dados = "const JB_CATALOGO_LOCAL = " + json.dumps(locais, ensure_ascii=False, indent=1) + ";"
    LOCAL_JS.write_text(js[:inicio] + dados + js[fim:], encoding="utf-8")
    print(f"{len(CATALOGO)} produtos · {len(galeria_sql)} imagens na galeria · seed.sql e catalogo-local.js atualizados")


if __name__ == "__main__":
    main()
