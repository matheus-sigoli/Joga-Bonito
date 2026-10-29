// ============================================================================
// JOGA BONITO — conteúdo editorial da vitrine (vitrine-info.js)
//   * craques: foto do jogador que vestiu a camisa (página inicial, produto, catálogo)
//   * histórias das camisas retrô
//   * ficha completa: detalhes da peça, medidas, cuidados, entrega e trocas
//   * estimativa de frete e prazo pelo CEP (mesma regra de frete da API)
// Carregado depois de api.js e layout.js.
// ============================================================================

// Craques que vestiram o manto: seção própria (craques.html e página inicial).
// As camisas da loja levam só o nome do time; aqui entram os jogadores.
// Foto: coloque o arquivo indicado em "foto" (IMG/Jogadores/). Sem a foto, aparece um
// cartão com o número e as cores do time — a página fica completa mesmo antes das imagens.
JB.craques = [
  {
    chave: "romario", produtoId: 13, jogador: "Romário", numero: "11", time: "Brasil", ano: "1994",
    cores: ["#F7D117", "#0B7A3B"], foto: "../IMG/Jogadores/romario-1994.jpg", largura: 600, altura: 504, foco: "50% 30%",
    alt: "Romário com a camisa amarela da Seleção Brasileira na Copa de 1994",
    titulo: "O baixinho do tetra",
    texto: "Cinco gols na Copa dos Estados Unidos e eleito o melhor jogador do torneio: Romário foi o nome do tetracampeonato do Brasil em 1994."
  },
  {
    chave: "kaka", produtoId: 19, jogador: "Kaká", numero: "22", time: "Milan", ano: "2006/07",
    cores: ["#C8102E", "#111111"], foto: "../IMG/Jogadores/kaka.jpg", largura: 1600, altura: 1118, foco: "30% 30%",
    alt: "Kaká com a camisa rubro-negra do Milan",
    titulo: "Atenas, 2007",
    texto: "Artilheiro da Champions League 2006/07, Kaká levou o Milan ao título na final de Atenas e ganhou a Bola de Ouro daquele ano."
  },
  {
    chave: "cristiano-ronaldo", produtoId: 15, jogador: "Cristiano Ronaldo", numero: "7", time: "Manchester United", ano: "2007/08",
    cores: ["#DA020E", "#FFFFFF"], foto: "../IMG/Jogadores/cr7-2008.jpg", largura: 1600, altura: 1303, foco: "52% 25%",
    retrato: "../IMG/Jogadores/cr7-2008-retrato.jpg",
    alt: "Cristiano Ronaldo morde a medalha da Champions League de 2008 com a camisa vermelha do Manchester United",
    titulo: "Moscou, 2008",
    texto: "Na temporada 2007/08, Cristiano marcou 42 gols, foi campeão inglês, venceu a Champions League em Moscou e ganhou sua primeira Bola de Ouro."
  },
  {
    chave: "mbappe", produtoId: 9, jogador: "Kylian Mbappé", numero: "10", time: "Real Madrid", ano: "2026/27",
    cores: ["#F7F7F5", "#1B2A4A"], foto: "../IMG/Jogadores/mbappe.jpg", largura: 1600, altura: 900, foco: "40% 30%",
    alt: "Mbappé comemora gol de braços abertos com a camisa branca do Real Madrid",
    titulo: "O branco do Bernabéu",
    texto: "Desde 2024 no Real Madrid, Mbappé virou o rosto do branco merengue — o mesmo branco liso da camisa 2026/27."
  },
  {
    chave: "lamine-yamal", produtoId: 10, jogador: "Lamine Yamal", numero: "10", time: "Barcelona", ano: "2026/27",
    cores: ["#A50044", "#EDBB00"], foto: "../IMG/Jogadores/lamine-yamal.jpg", largura: 1200, altura: 800, foco: "55% 22%",
    alt: "Lamine Yamal com a camisa azul-grená do Barcelona",
    titulo: "A nova joia do Camp Nou",
    texto: "Formado nas categorias de base do Barcelona, estreou no time principal aos 15 anos e foi campeão da Eurocopa de 2024 pela Espanha aos 17. O azul-grená da nova geração."
  }
];
JB.craquePorProduto = id => JB.craques.find(c => c.produtoId === Number(id)) || null;

/** Foto do craque; se o arquivo ainda não existir, vira o cartão com número e cores do time. */
JB.fotoCraque = (c, classe = "craque-foto", carregar = "lazy") =>
  `<img class="${classe}" src="${c.foto}" alt="${JB.esc(c.alt)}" ${c.largura ? `width="${c.largura}" height="${c.altura}"` : ""}
        loading="${carregar}" style="--foco:${c.foco}" data-fallback="craque" data-numero="${JB.esc(c.numero)}"
        data-nome="${JB.esc(c.jogador)}" data-time="${JB.esc(`${c.time} · ${c.ano}`)}" data-cor1="${c.cores[0]}" data-cor2="${c.cores[1]}">`;

// Histórias das camisas retrô — do TIME (os jogadores ficam na seção de craques)
JB.historias = {
  13: "Copa de 1994, nos Estados Unidos: o Brasil venceu a Itália nos pênaltis em Pasadena e conquistou o tetra, 24 anos depois do tri.",
  14: "México, 1986: a Argentina venceu a Alemanha Ocidental por 3 a 2 na final do Estádio Azteca e conquistou o bicampeonato mundial.",
  15: "Temporada 2007/08: o Manchester United foi campeão inglês e venceu o Chelsea nos pênaltis em Moscou, na final da Champions League.",
  16: "2012: o Corinthians foi campeão invicto da Libertadores e, em dezembro, venceu o Chelsea por 1 a 0 no Japão para conquistar o Mundial de Clubes.",
  17: "O Barcelona 2005/06 foi campeão espanhol e conquistou a Champions League em Paris, de virada sobre o Arsenal.",
  18: "Ano do centenário: o Real Madrid venceu o Bayer Leverkusen por 2 a 1 em Glasgow e conquistou a sua nona Champions League.",
  19: "O Milan venceu o Liverpool por 2 a 1 na final de Atenas, conquistou a sua sétima Champions League e, no fim do ano, o Mundial de Clubes.",
  20: "Com José Mourinho no comando, a Inter de 2009/10 ganhou o Campeonato Italiano, a Copa da Itália e a Champions — a primeira tríplice coroa de um clube italiano.",
  21: "Em 2000 o Boca Juniors ganhou a Libertadores e, em Tóquio, venceu o Real Madrid por 2 a 1 no Intercontinental.",
  22: "O Santos de 2011 venceu o Peñarol na final e conquistou o tri da Libertadores, 48 anos depois do bicampeonato da década de 1960.",
  23: "Cardiff, 2017: 4 a 1 na Juventus. O Real Madrid foi o primeiro clube a ganhar duas Champions League seguidas no formato atual.",
  24: "A Fiorentina de 1998/99 liderou boa parte do Campeonato Italiano, terminou em terceiro e voltou à Champions League com a camisa roxa da Viola."
};

JB.fichaProduto = (() => {
  function detalhes(p) {
    if (p.tipo === "Chuteira" || p.marca) {
      const piso = {
        Futsal: ["Solado IC de borracha lisa, que não marca a quadra", "Amortecimento no calcanhar para os arranques curtos"],
        Society: ["Solado TF com travas baixas de borracha para grama sintética", "Entressola que distribui o impacto em pisos duros"],
        Campo: ["Solado FG com travas para grama natural firme", "Placa leve para tração em mudanças de direção"]
      }[p.linha] || [];
      return [
        ["Marca", p.marca], ["Solado", p.solado], ["Piso", p.linha],
        ...piso.map(t => ["", t]),
        ["Cabedal", "Sintético com ajuste firme ao pé"],
        ["Numeração", "BR 37 a 44 (veja o guia de medidas)"]
      ];
    }
    const retro = p.categoriaSlug === "retro";
    return [
      ["Equipe", p.equipe], ["Linha", p.linha], [retro ? "Ano de referência" : "Temporada", p.ano],
      ["Modelo", retro ? "Reedição com o corte da época (mais solto que o atual)" : "Torcedor, corte regular"],
      ["Tecido", retro ? "Malha de poliéster com toque macio, como as camisas dos anos 80 e 90" : "Malha leve de poliéster com secagem rápida"],
      ["Escudo", "Bordado"],
      ["Tamanhos", "P ao XG (veja o guia de medidas)"]
    ];
  }

  function cuidados(p) {
    return p.tipo === "Chuteira" || p.marca
      ? ["Limpe com pano úmido e sabão neutro logo depois do jogo.", "Seque à sombra, com papel dentro para manter a forma — nunca no sol ou no secador.",
         "Não lave na máquina.", "Troque as palmilhas de lugar entre um jogo e outro para ventilar."]
      : ["Lave do avesso, em água fria, com cores parecidas.", "Não use alvejante nem amaciante (o amaciante tira a respirabilidade do tecido).",
         "Não passe ferro sobre escudo, números e patrocínios.", "Seque à sombra, no cabide."];
  }

  // Regiões pelo primeiro dígito do CEP (estimativa a partir de São Paulo, de onde a loja envia)
  const regioes = {
    0: ["Grande São Paulo", 1, 3], 1: ["Interior e litoral de SP", 2, 4], 2: ["RJ e ES", 3, 5], 3: ["Minas Gerais", 3, 6],
    4: ["BA e SE", 5, 8], 5: ["PE, AL, PB e RN", 6, 9], 6: ["Norte, CE, PI e MA", 7, 12],
    7: ["Centro-Oeste, TO e RO", 5, 8], 8: ["PR e SC", 3, 6], 9: ["Rio Grande do Sul", 4, 7]
  };

  function estimarEntrega(cep, valor) {
    const digitos = String(cep || "").replace(/\D/g, "");
    if (digitos.length !== 8) return null;
    const [regiao, min, max] = regioes[digitos[0]];
    const gratis = valor >= JB.LIMITE_FRETE_GRATIS;
    return { regiao, prazo: `${min} a ${max} dias úteis`, frete: gratis ? 0 : JB.VALOR_FRETE, gratis };
  }

  function linhas(lista) {
    return lista.filter(([, v]) => v !== null && v !== undefined && v !== "")
      .map(([k, v]) => k ? `<div><dt>${JB.esc(k)}</dt><dd>${JB.esc(String(v))}</dd></div>` : `<div class="ficha-nota"><dd>${JB.esc(v)}</dd></div>`).join("");
  }

  function tabelaMedidas(p) {
    const t = (JB.tabelasMedidas || {})[p.tipo === "Chuteira" || p.marca ? "chuteira" : "camisa"];
    if (!t) return "";
    return `<table class="tabela">
        <caption class="sr-only">${JB.esc(t.titulo)}</caption>
        <thead><tr>${t.cabecalho.map(c => `<th scope="col">${JB.esc(c)}</th>`).join("")}</tr></thead>
        <tbody>${t.linhas.map(l => `<tr>${l.map((c, i) => i === 0 ? `<th scope="row">${JB.esc(c)}</th>` : `<td>${JB.esc(c)}</td>`).join("")}</tr>`).join("")}</tbody>
      </table><p class="texto-suave">${JB.esc(t.dica)}</p>`;
  }

  /** Abas da ficha completa (padrão WAI-ARIA: setas, Home e End). */
  function montar(alvo, p) {
    const final = p.precoFinal ?? p.preco;
    const abas = [
      ["detalhes", "Detalhes da peça", `<dl class="ficha ficha-larga">${linhas(detalhes(p))}</dl>`],
      ["medidas", "Medidas", tabelaMedidas(p)],
      ["cuidados", "Cuidados", `<ul class="lista-check">${cuidados(p).map(c => `<li>${JB.esc(c)}</li>`).join("")}</ul>`],
      ["entrega", "Entrega e trocas", `
        <ul class="lista-check">
          <li>Frete grátis em compras a partir de ${JB.brl(JB.LIMITE_FRETE_GRATIS)}; abaixo disso, ${JB.brl(JB.VALOR_FRETE)} para todo o Brasil.</li>
          <li>Enviamos de São Paulo com código de rastreio, que aparece em Meus pedidos.</li>
          <li>Primeira troca de tamanho grátis em até 30 dias, com etiqueta.</li>
          <li>Arrependeu? Devolução em até 7 dias do recebimento, com o valor de volta (Código de Defesa do Consumidor, art. 49).</li>
          <li>Pagamento por Pix, cartão de crédito em até 6x sem juros (${JB.brl(final / 6)} por mês) ou débito.</li>
          <li>Joga Junto: ${JB.brl(Math.round(final) / 100)} desta peça vão para o programa social da loja.</li>
        </ul>`]
    ];
    alvo.innerHTML = `
      <div class="abas-ficha" role="tablist" aria-label="Informações do produto">
        ${abas.map(([id, nome], i) => `<button role="tab" id="aba-ficha-${id}" aria-controls="painel-ficha-${id}"
            aria-selected="${i === 0}" ${i ? 'tabindex="-1"' : ""}>${nome}</button>`).join("")}
      </div>
      ${abas.map(([id, , html], i) => `<div class="painel-ficha" role="tabpanel" id="painel-ficha-${id}"
          aria-labelledby="aba-ficha-${id}" tabindex="0" ${i ? "hidden" : ""}>${html}</div>`).join("")}`;

    const botoes = [...alvo.querySelectorAll("[role=tab]")];
    function escolher(b, focar) {
      botoes.forEach(x => {
        const sel = x === b;
        x.setAttribute("aria-selected", sel);
        x.tabIndex = sel ? 0 : -1;
        document.getElementById(x.getAttribute("aria-controls")).hidden = !sel;
      });
      if (focar) b.focus();
    }
    botoes.forEach((b, i) => {
      b.addEventListener("click", () => escolher(b));
      b.addEventListener("keydown", e => {
        const destino = { ArrowRight: i + 1, ArrowLeft: i - 1, Home: 0, End: botoes.length - 1 }[e.key];
        if (destino === undefined) return;
        e.preventDefault();
        escolher(botoes[(destino + botoes.length) % botoes.length], true);
      });
    });
  }

  return { montar, estimarEntrega, detalhes };
})();

/** Card completo (craques.html): foto grande do jogador, a história e a camisa à venda. */
JB.cardCraque = (c, p) => {
  if (!c) return "";
  const final = p ? (p.precoFinal ?? p.preco) : null;
  return `
    <article class="craque revelar" id="${c.chave}">
      ${JB.fotoCraque(c)}
      <div class="craque-texto">
        <p class="craque-nome">${JB.esc(c.jogador)} · ${JB.esc(c.time)} ${JB.esc(c.ano)}</p>
        <h3>${JB.esc(c.titulo)}</h3>
        <p>${JB.esc(c.texto)}</p>
        ${p ? `<a class="craque-produto" href="Produtos.html?id=${p.id}">
          <img src="${JB.esc(p.img)}" alt="" width="96" height="96" loading="lazy" data-fallback="logo">
          <span><strong>${JB.esc(p.nome)}</strong><span>${JB.brl(final)} · 6x de ${JB.brl(final / 6)}</span></span>
          <span class="craque-seta" aria-hidden="true">→</span>
        </a>` : ""}
      </div>
    </article>`;
};

/** Card compacto (página inicial): foto, nome, time e ano. */
JB.cardCraqueCompacto = c => `
  <a class="craque-mini revelar" href="craques.html#${c.chave}">
    ${JB.fotoCraque(c, "craque-mini-foto")}
    <span class="craque-mini-texto"><strong>${JB.esc(c.jogador)}</strong><span>${JB.esc(c.time)} · ${JB.esc(c.ano)}</span></span>
  </a>`;
