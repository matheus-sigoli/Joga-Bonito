// ============================================================================
// JOGA BONITO — página do produto (produto.js)
// Galeria, seleção de tamanho com estoque real, carrinho e avaliações.
// ============================================================================

(async () => {
  const id = Number(JB.parametro("id"));
  const $ = sel => document.getElementById(sel);
  let produto = null;
  let fotoAtual = 0;
  let tamanho = null;
  let qtd = 1;

  if (!id) return mostrarErro("Produto não informado.");

  try {
    produto = await JB.catalogo.detalhe(id);
  } catch (e) {
    return mostrarErro(e.status === 404 ? "Este produto não existe ou saiu do catálogo." : e.message);
  }


  renderizar();
  carregarAvaliacoes();
  carregarRecomendados();

  // ---------------------------------------------------------------------------
  function mostrarErro(msg) {
    $("produto-erro").hidden = false;
    $("produto-erro").innerHTML = `<div class="icone-grande">404</div><p>${JB.esc(msg)}</p><p><a class="btn btn-primario" href="catalogo.html">Ver catálogo</a></p>`;
  }

  function renderizar() {
    document.title = `${produto.nome} — Joga Bonito`;
    $("produto").hidden = false;
    $("trilha-produto").textContent = produto.nome;
    $("trilha-categoria").textContent = produto.categoria;
    $("trilha-categoria").href = `catalogo.html?categoria=${produto.categoriaSlug}`;
    $("produto-modelo").textContent = produto.marca ? JB.rotuloProduto(produto) : produto.modelo;
    $("produto-nome").textContent = produto.nome;
    $("produto-descricao").textContent = produto.descricao;

    // Ficha técnica: campos da planilha (camisa: linha/equipe/ano · chuteira: marca/solado/piso)
    const ficha = produto.marca
      ? [["Marca", produto.marca], ["Tipo de solado", produto.solado], ["Piso", produto.linha]]
      : [["Linha", produto.linha], ["Equipe", produto.equipe],
         [produto.categoriaSlug === "retro" ? "Ano de referência" : "Temporada", produto.ano]];
    $("produto-descricao").insertAdjacentHTML("afterend", `<dl class="ficha">${ficha.filter(([, v]) => v)
      .map(([k, v]) => `<div><dt>${JB.esc(k)}</dt><dd>${JB.esc(String(v))}</dd></div>`).join("")}</dl>`);
    $("produto-nota").innerHTML = produto.totalAvaliacoes > 0
      ? `${JB.estrelas(produto.notaMedia)} <a href="#avaliacoes">${Number(produto.notaMedia).toFixed(1)} · ${produto.totalAvaliacoes} avaliaç${produto.totalAvaliacoes === 1 ? "ão" : "ões"}</a>`
      : '<span class="texto-suave">Ainda sem avaliações</span>';

    const promo = produto.precoPromocional && produto.precoPromocional < produto.preco;
    const final = produto.precoFinal ?? produto.preco;
    $("produto-preco").innerHTML = `
      ${promo ? `<s>${JB.brl(produto.preco)}</s> <span class="selo selo-promo">-${Math.round((1 - produto.precoPromocional / produto.preco) * 100)}%</span>` : ""}
      <strong>${JB.brl(final)}</strong>
      <span class="parcelas">ou 6x de ${JB.brl(final / 6)} sem juros</span>`;

    // Galeria
    const fotos = produto.imgs?.length ? produto.imgs : [produto.img];
    $("miniaturas").innerHTML = fotos.map((src, i) =>
      `<button type="button" data-i="${i}" aria-label="Foto ${i + 1}"><img src="${JB.esc(src)}" alt="" loading="lazy" data-fallback="remover-botao"></button>`).join("");
    $("miniaturas").addEventListener("click", e => {
      const b = e.target.closest("button");
      if (b) trocarFoto(Number(b.dataset.i));
    });
    $("foto-anterior").onclick = () => trocarFoto(fotoAtual - 1);
    $("foto-proxima").onclick = () => trocarFoto(fotoAtual + 1);
    $("foto-principal").dataset.fallback = "logo";
    // Uma imagem só (ilustração): sem setas nem miniaturas
    const variasFotos = fotos.length > 1;
    $("miniaturas").hidden = !variasFotos;
    $("foto-anterior").hidden = !variasFotos;
    $("foto-proxima").hidden = !variasFotos;
    $("foto-principal").onclick = abrirZoom;
    $("foto-principal").onkeydown = e => { if (e.key === "Enter") abrirZoom(); };
    trocarFoto(0);

    // Tamanhos
    const ehChuteira = produto.tipo === "Chuteira";
    $("rotulo-tamanho").textContent = ehChuteira ? "Escolha a numeração" : "Escolha o tamanho";
    $("abrir-guia").onclick = () => JB.abrirGuiaMedidas(ehChuteira ? "chuteira" : "camisa");
    $("tamanhos").innerHTML = (produto.tamanhos || []).map(t => `
      <button type="button" role="radio" aria-checked="false" data-tamanho="${JB.esc(t.tamanho)}"
        ${t.quantidade === 0 ? 'disabled aria-label="' + JB.esc(t.tamanho) + ' esgotado"' : ""}>${JB.esc(t.tamanho)}</button>`).join("");
    $("tamanhos").addEventListener("click", e => {
      const b = e.target.closest("button:not(:disabled)");
      if (b) escolherTamanho(b.dataset.tamanho);
    });

    if ((produto.tamanhos || []).every(t => t.quantidade === 0)) {
      $("btn-adicionar").disabled = true;
      $("btn-adicionar").textContent = "Esgotado";
    }

    montarExtras();

    $("qtd-menos").onclick = () => mudarQtd(-1);
    $("qtd-mais").onclick = () => mudarQtd(1);
    $("btn-adicionar").onclick = adicionar;
  }

  // História da camisa (retrô), ficha completa e frete por CEP
  function montarExtras() {
    // A ficha fala só do time; os jogadores ficam na página de craques (craques.html)
    const historia = JB.historias[produto.id];
    const secao = $("em-campo");
    if (historia) {
      secao.classList.add("em-campo-historia");
      secao.innerHTML = `
        <p class="em-campo-ano" aria-hidden="true">${JB.esc(String(produto.ano || ""))}</p>
        <div class="em-campo-texto">
          <p class="craque-nome">${JB.esc(produto.equipe || "")} · ${JB.esc(String(produto.ano || ""))}</p>
          <h2 class="titulo-secao" id="titulo-em-campo">A história da camisa</h2>
          <p class="lead">${JB.esc(historia)}</p>
        </div>`;
      secao.hidden = false;
    }

    JB.fichaProduto.montar($("ficha-abas"), produto);
    $("ficha-completa").hidden = false;

    const cep = $("cep-frete");
    cep.addEventListener("input", () => {
      const d = cep.value.replace(/\D/g, "").slice(0, 8);
      cep.value = d.length > 5 ? `${d.slice(0, 5)}-${d.slice(5)}` : d;
    });
    $("form-frete").addEventListener("submit", e => {
      e.preventDefault();
      const valor = (produto.precoFinal ?? produto.preco) * qtd;
      const r = JB.fichaProduto.estimarEntrega(cep.value, valor);
      $("frete-resultado").innerHTML = !r
        ? '<span class="erro-texto">Digite os 8 números do CEP.</span>'
        : `<strong>${r.gratis ? "Frete grátis" : JB.brl(r.frete)}</strong> · ${JB.esc(r.regiao)} · chega em ${r.prazo} depois da confirmação do pagamento`;
    });
  }

  function trocarFoto(i) {
    const fotos = [...$("miniaturas").querySelectorAll("button")];
    if (!fotos.length) { $("foto-principal").src = produto.img; return; }
    fotoAtual = (i + fotos.length) % fotos.length;
    $("foto-principal").src = fotos[fotoAtual].querySelector("img").src;
    $("foto-principal").alt = `${produto.nome} — foto ${fotoAtual + 1}`;
    fotos.forEach((b, k) => b.classList.toggle("ativa", k === fotoAtual));
  }

  function abrirZoom() {
    $("zoom-img").src = $("foto-principal").src;
    $("zoom-img").alt = $("foto-principal").alt;
    $("zoom").showModal();
  }

  function estoqueDo(t) {
    return (produto.tamanhos || []).find(x => x.tamanho === t)?.quantidade ?? 0;
  }

  function escolherTamanho(t) {
    tamanho = t;
    $("tamanhos").querySelectorAll("button").forEach(b => {
      const sel = b.dataset.tamanho === t;
      b.classList.toggle("selecionado", sel);
      b.setAttribute("aria-checked", sel);
    });
    const disp = estoqueDo(t);
    $("estoque-info").textContent = disp < 5 ? `Últimas ${disp} unidade${disp > 1 ? "s" : ""} neste tamanho` : "✓ Em estoque";
    $("estoque-info").className = `estoque-info ${disp < 5 ? "nivel-baixo" : "nivel-regular"}`;
    $("erro-tamanho").textContent = "";
    qtd = Math.min(qtd, disp);
    $("qtd").textContent = qtd;
  }

  function mudarQtd(delta) {
    const max = tamanho ? Math.min(estoqueDo(tamanho), 10) : 10;
    qtd = Math.max(1, Math.min(qtd + delta, max));
    $("qtd").textContent = qtd;
  }

  function adicionar() {
    if (!tamanho) {
      $("erro-tamanho").textContent = "Escolha um tamanho antes de adicionar ao carrinho.";
      $("tamanhos").querySelector("button:not(:disabled)")?.focus();
      return;
    }
    const noCarrinho = JB.carrinho.itens().find(i => i.id === produto.id && i.tamanho === tamanho)?.qtd || 0;
    if (noCarrinho + qtd > estoqueDo(tamanho)) {
      $("erro-tamanho").textContent = `Você já tem ${noCarrinho} no carrinho e só há ${estoqueDo(tamanho)} disponíveis.`;
      return;
    }
    JB.carrinho.adicionar(produto, tamanho, qtd);
    JB.toast(`${produto.nome} (${tamanho}) adicionado ao carrinho`);
  }

  // ------------------------------ Avaliações ---------------------------------
  async function carregarAvaliacoes() {
    let lista = [];
    try { lista = await JB.api(`/api/produtos/${id}/avaliacoes`); } catch { return; }
    $("avaliacoes").hidden = false;

    const total = lista.length;
    const media = total ? lista.reduce((s, a) => s + a.nota, 0) / total : 0;
    $("avaliacoes-resumo").innerHTML = total
      ? `<p class="media">${media.toFixed(1)}</p>${JB.estrelas(media)}<p class="texto-suave">${total} avaliaç${total === 1 ? "ão" : "ões"}</p>
         ${[5, 4, 3, 2, 1].map(n => {
           const q = lista.filter(a => a.nota === n).length;
           return `<div class="barra-nota"><span>${n}★</span><div><i style="width:${(q / total) * 100}%"></i></div><span>${q}</span></div>`;
         }).join("")}`
      : '<p class="texto-suave">Seja o primeiro a avaliar este produto.</p>';

    $("lista-avaliacoes").innerHTML = lista.map(a => `
      <article class="avaliacao">
        <div class="avaliacao-topo">${JB.estrelas(a.nota)} <strong>${JB.esc(a.cliente)}</strong> <span class="texto-suave">${JB.data(a.data)}</span></div>
        ${a.comentario ? `<p>${JB.esc(a.comentario)}</p>` : ""}
      </article>`).join("");

    if (JB.sessao.logado()) {
      const form = $("form-avaliacao");
      form.hidden = false;
      form.onsubmit = async e => {
        e.preventDefault();
        const nota = Number(form.querySelector("input[name=nota]:checked")?.value);
        if (!nota) return JB.aviso($("aviso-avaliacao"), "Escolha de 1 a 5 estrelas.");
        try {
          const r = await JB.api(`/api/produtos/${id}/avaliacoes`, {
            metodo: "POST", autenticado: true, corpo: { nota, comentario: $("comentario").value.trim() || null }
          });
          JB.toast((r && r.mensagem) || "Obrigado pela avaliação!");
          form.reset();
          JB.aviso($("aviso-avaliacao"), "");
          carregarAvaliacoes();
        } catch (err) {
          JB.aviso($("aviso-avaliacao"), err.message);
        }
      };
    }
  }

  async function carregarRecomendados() {
    try {
      const lista = await JB.catalogo.listar({ categoria: produto.categoriaSlug });
      const sugestoes = lista.filter(p => p.id !== produto.id && p.estoque > 0).slice(0, 4);
      $("recomendados").innerHTML = sugestoes.map(JB.cardProduto).join("");
    } catch { /* opcional */ }
  }
})();
