// ============================================================================
// JOGA BONITO — painel administrativo (admin.js)
// Todas as rotas /api/admin exigem token JWT com perfil "Admin".
// ============================================================================

(() => {
  const $ = id => document.getElementById(id);
  if (!JB.exigirLogin()) return;
  if (!JB.sessao.ehAdmin()) {
    document.getElementById("conteudo").innerHTML =
      '<div class="vazio painel"><div class="icone-grande">Restrito</div><p>Esta área é exclusiva para administradores.</p><p><a class="btn btn-primario" href="inicial.html">Voltar à loja</a></p></div>';
    return;
  }
  if (JB.API_BASE) $("link-swagger").href = `${JB.API_BASE}/swagger`;
  if (window.JB_CONFIG && window.JB_CONFIG.modo === "demo") $("link-swagger").hidden = true;   // site público: sem API

  const STATUS = ["Pago", "Em Separação", "Enviado", "Entregue", "Cancelado"];
  const classe = s => "st-" + s.toLowerCase().replace(/\s+/g, "-");
  const erro = e => JB.aviso($("aviso-admin"), e.message);
  let estoque = [];
  let produtos = [];
  let categorias = [];

  // ------------------------------------------------------------------ Abas
  const carregadores = { visao: carregarVisao, pedidos: carregarPedidos, estoque: carregarEstoque, produtos: carregarProdutos, banco: carregarConsultas, avaliacoes: carregarAvaliacoes, acessos: carregarAcessos };
  const abas = [...document.querySelectorAll('[role="tab"]')];
  abas.forEach((tab, i) => {
    tab.addEventListener("click", () => abrir(tab.id.replace("tab-", "")));
    // Teclado (padrão WAI-ARIA): setas trocam de aba, Home/End vão para a primeira/última
    tab.addEventListener("keydown", e => {
      const destino = { ArrowRight: i + 1, ArrowLeft: i - 1, Home: 0, End: abas.length - 1 }[e.key];
      if (destino === undefined) return;
      e.preventDefault();
      const alvo = abas[(destino + abas.length) % abas.length];
      abrir(alvo.id.replace("tab-", ""));
      alvo.focus();
    });
  });

  function abrir(nome) {
    abas.forEach(t => {
      const ativa = t.id === `tab-${nome}`;
      t.setAttribute("aria-selected", ativa);
      t.tabIndex = ativa ? 0 : -1;
    });
    document.querySelectorAll('[role="tabpanel"]').forEach(p => p.hidden = p.id !== `aba-${nome}`);
    JB.aviso($("aviso-admin"), "");
    location.hash = nome;
    carregadores[nome]();
  }

  // ------------------------------------------------- Status das conexões
  async function carregarConexoes() {
    const area = $("status-conexoes");
    const item = (nome, ok, detalhe) =>
      `<span class="conexao ${ok ? "ok" : "falha"}"><i aria-hidden="true"></i><strong>${JB.esc(nome)}</strong> ${JB.esc(detalhe)}</span>`;
    try {
      const inicio = performance.now();
      const r = await fetch(`${JB.API_BASE}/health/ready`, { cache: "no-store", credentials: "include" });
      const dados = await r.json();
      const api = item("API", true, `${Math.round(performance.now() - inicio)} ms`);
      const banco = (dados.componentes || []).map(c =>
        item(c.nome === "sqlserver" ? "SQL Server" : c.nome, c.status === "Healthy", `${c.status === "Healthy" ? "conectado" : "sem conexão"} · ${c.duracaoMs} ms`));
      area.innerHTML = api + banco.join("");
    } catch {
      area.innerHTML = item("API", false, "sem resposta");
    }
  }

  // --------------------------------------------------------- Visão geral
  async function carregarVisao() {
    carregarConexoes();
    try {
      const d = await JB.api("/api/admin/dashboard", { autenticado: true });
      const kpis = [
        ["Faturamento total", JB.brl(d.faturamentoTotal), `${d.totalPedidos} pedidos`],
        ["Últimos 30 dias", JB.brl(d.faturamento30Dias), `Ticket médio ${JB.brl(d.ticketMedio30Dias)}`],
        ["A despachar", d.pedidosPendentesEnvio, "pagos ou em separação"],
        ["Clientes", d.totalClientes, "contas ativas"],
        ["Peças em estoque", d.totalPecasEstoque, `${d.totalProdutos} produtos ativos`],
        ["Alertas de estoque", d.tamanhosEsgotados + d.tamanhosEstoqueBaixo, `${d.tamanhosEsgotados} esgotados · ${d.tamanhosEstoqueBaixo} baixos`],
        ["Joga Junto", JB.brl(d.totalJogaJunto || 0), "1% dos pedidos para escolinhas"],
        ["Avaliações a moderar", d.avaliacoesPendentes || 0, "aba Avaliações"]
      ];
      const contador = $("contador-pendentes");
      contador.textContent = d.avaliacoesPendentes || "";
      contador.hidden = !d.avaliacoesPendentes;
      $("kpis").innerHTML = kpis.map(([t, v, s]) => `<div class="kpi painel"><p>${t}</p><strong>${v}</strong><small>${s}</small></div>`).join("");

      const max = Math.max(1, ...d.vendasPorCategoria.map(c => c.receita));
      $("grafico-categorias").innerHTML = d.vendasPorCategoria.length
        ? d.vendasPorCategoria.map(c => `
            <div class="barra-cat">
              <div class="barra-cat-topo"><span>${JB.esc(c.categoria)}</span><strong>${JB.brl(c.receita)}</strong></div>
              <div class="barra"><i style="width:${(c.receita / max) * 100}%"></i></div>
              <small class="texto-suave">${c.unidades} unidade(s)</small>
            </div>`).join("")
        : '<p class="texto-suave">Sem vendas no período.</p>';

      $("mais-vendidos").innerHTML = d.maisVendidos.length
        ? d.maisVendidos.map(m => `<li><span>${JB.esc(m.nome)}</span><small class="texto-suave">${m.unidades} un · ${JB.brl(m.receita)}</small></li>`).join("")
        : '<li class="texto-suave">Sem vendas ainda.</li>';
    } catch (e) { erro(e); }
  }

  // --------------------------------------------------------------- Pedidos
  async function carregarPedidos() {
    const status = $("filtro-status").value;
    try {
      const lista = await JB.api(`/api/admin/pedidos${status ? `?status=${encodeURIComponent(status)}` : ""}`, { autenticado: true });
      $("tabela-pedidos").innerHTML = lista.length ? lista.map(p => {
        const finalizado = ["Entregue", "Cancelado"].includes(p.status);
        const opcoes = STATUS.filter(s => s !== p.status && !(s === "Cancelado" && p.status === "Enviado") &&
          (s === "Cancelado" || STATUS.indexOf(s) > STATUS.indexOf(p.status)));
        return `<tr>
          <td>${p.id}</td>
          <td>${JB.dataHora(p.data)}</td>
          <td>${JB.esc(p.cliente)}</td>
          <td>${p.itens.map(i => `${i.qtd}× ${JB.esc(i.nome)} (${JB.esc(i.tamanho)})`).join("<br>")}</td>
          <td>${JB.brl(p.total)}</td>
          <td>${JB.esc(p.formaPagamento)}${p.parcelas > 1 ? ` ${p.parcelas}x` : ""}</td>
          <td>${JB.esc(p.origem)}</td>
          <td><span class="etiqueta ${classe(p.status)}">${JB.esc(p.status)}</span></td>
          <td>${finalizado ? "—" : `
            <select class="entrada entrada-pequena" data-pedido="${p.id}" aria-label="Novo status do pedido ${p.id}">
              <option value="">Mudar para…</option>${opcoes.map(o => `<option>${o}</option>`).join("")}
            </select>`}</td>
        </tr>`;
      }).join("") : '<tr><td colspan="9" class="texto-suave">Nenhum pedido.</td></tr>';
    } catch (e) { erro(e); }
  }
  $("filtro-status").addEventListener("change", carregarPedidos);
  $("tabela-pedidos").addEventListener("change", async e => {
    const sel = e.target.closest("select[data-pedido]");
    if (!sel || !sel.value) return;
    if (sel.value === "Cancelado" && !confirm(`Cancelar o pedido #${sel.dataset.pedido}? O estoque será devolvido.`)) { sel.value = ""; return; }
    try {
      await JB.api(`/api/admin/pedidos/${sel.dataset.pedido}/status`, { metodo: "PUT", autenticado: true, corpo: { status: sel.value } });
      JB.toast(`Pedido #${sel.dataset.pedido} → ${sel.value}`);
      carregarPedidos();
    } catch (err) { erro(err); sel.value = ""; }
  });

  // --------------------------------------------------------------- Estoque
  async function carregarEstoque() {
    try {
      const [rel, aud] = await Promise.all([
        JB.api("/api/admin/estoque", { autenticado: true }),
        JB.api("/api/admin/estoque/auditoria?limite=40", { autenticado: true })
      ]);
      estoque = rel;
      renderEstoque();
      $("tabela-auditoria").innerHTML = aud.map(a => `<tr>
        <td>${JB.dataHora(a.data)}</td><td>${JB.esc(a.produto)}</td><td>${JB.esc(a.tamanho)}</td>
        <td>${a.qtdAnterior}</td><td>${a.qtdNova}</td><td>${JB.esc(a.origem)}</td></tr>`).join("");
    } catch (e) { erro(e); }
  }

  function renderEstoque() {
    const termo = $("busca-estoque").value.trim().toLowerCase();
    const criticos = $("so-criticos").checked;
    const porProduto = new Map();
    estoque.forEach(l => {
      if (!porProduto.has(l.produtoId)) porProduto.set(l.produtoId, { ...l, tamanhos: [] });
      porProduto.get(l.produtoId).tamanhos.push(l);
    });
    const linhas = [...porProduto.values()]
      .filter(p => !termo || p.nome.toLowerCase().includes(termo))
      .filter(p => !criticos || p.tamanhos.some(t => t.statusNivel !== "REGULAR"));
    $("tabela-estoque").innerHTML = linhas.map(p => `<tr>
      <td><strong>${JB.esc(p.nome)}</strong><br><small class="texto-suave">${JB.esc(p.linha)}</small></td>
      <td>${JB.esc(p.categoria)}</td>
      <td><div class="grade-estoque">${p.tamanhos.map(t => `
        <label class="celula-estoque nivel-${t.statusNivel.toLowerCase()}" title="${t.statusNivel}">
          <span>${JB.esc(t.tamanho)}</span>
          <input type="number" min="0" max="9999" value="${t.quantidade}" data-produto="${p.produtoId}" data-tamanho="${JB.esc(t.tamanho)}"
            aria-label="Estoque de ${JB.esc(p.nome)} tamanho ${JB.esc(t.tamanho)}">
        </label>`).join("")}</div></td>
    </tr>`).join("") || '<tr><td colspan="3" class="texto-suave">Nada encontrado.</td></tr>';
  }
  $("busca-estoque").addEventListener("input", renderEstoque);
  $("so-criticos").addEventListener("change", renderEstoque);
  $("tabela-estoque").addEventListener("change", async e => {
    const inp = e.target.closest("input[data-produto]");
    if (!inp) return;
    const quantidade = Number(inp.value);
    if (!Number.isInteger(quantidade) || quantidade < 0) { JB.toast("Quantidade inválida.", "erro"); return; }
    try {
      await JB.api("/api/admin/estoque", {
        metodo: "PUT", autenticado: true,
        corpo: { produtoId: Number(inp.dataset.produto), tamanho: inp.dataset.tamanho, quantidade }
      });
      JB.toast(`Estoque atualizado: ${inp.dataset.tamanho} = ${quantidade}`);
      carregarEstoque();
    } catch (err) { erro(err); }
  });

  // -------------------------------------------------------------- Produtos
  const LINHAS = { chuteiras: ["Campo", "Society", "Futsal"], outras: ["Clube", "Seleção"] };

  async function carregarProdutos() {
    try {
      [produtos, categorias] = await Promise.all([JB.api("/api/produtos"), JB.api("/api/categorias")]);
      $("p-categoria").innerHTML = categorias.map(c => `<option value="${c.id}" data-slug="${c.slug}">${JB.esc(c.nome)}</option>`).join("");
      atualizarLinhas();
      $("tabela-produtos").innerHTML = produtos.map(p => `<tr>
        <td>${p.id}</td>
        <td><a href="Produtos.html?id=${p.id}" target="_blank">${JB.esc(p.nome)}</a></td>
        <td>${JB.esc(p.linha)}</td>
        <td>${JB.brl(p.precoFinal)}</td>
        <td>${p.estoque}</td>
        <td class="acoes-tabela">
          <button class="btn btn-contorno btn-pequeno" data-editar="${p.id}">Editar</button>
          <button class="btn btn-perigo btn-pequeno" data-remover="${p.id}" aria-label="Desativar ${JB.esc(p.nome)}">✕</button>
        </td></tr>`).join("");
    } catch (e) { erro(e); }
  }

  function atualizarLinhas(valor) {
    const slug = $("p-categoria").selectedOptions[0]?.dataset.slug;
    const linhas = slug === "chuteiras" ? LINHAS.chuteiras : LINHAS.outras;
    $("p-linha").innerHTML = linhas.map(l => `<option>${l}</option>`).join("");
    if (valor && linhas.includes(valor)) $("p-linha").value = valor;
    // Camisa: clube/seleção e ano · Chuteira: marca e tipo de solado (campos da planilha)
    $("campos-camisa").hidden = slug === "chuteiras";
    $("campos-chuteira").hidden = slug !== "chuteiras";
  }
  $("p-categoria").addEventListener("change", () => atualizarLinhas());

  function limparForm() {
    $("form-produto").reset();
    $("produto-id").value = "";
    $("titulo-form-produto").textContent = "Novo produto";
    JB.aviso($("aviso-produto"), "");
    atualizarLinhas();
  }
  $("novo-produto").addEventListener("click", limparForm);

  $("tabela-produtos").addEventListener("click", async e => {
    const editar = e.target.closest("[data-editar]");
    const remover = e.target.closest("[data-remover]");
    if (editar) {
      try {
        const d = await JB.api(`/api/produtos/${editar.dataset.editar}`);
        const p = d.produto;
        $("produto-id").value = p.id;
        $("titulo-form-produto").textContent = `Editar #${p.id}`;
        $("p-categoria").value = p.categoriaId;
        atualizarLinhas(p.linha);
        $("p-nome").value = p.nome;
        $("p-modelo").value = p.modelo;
        $("p-equipe").value = p.equipe || "";
        $("p-ano").value = p.ano || "";
        $("p-marca").value = p.marca || "";
        if (p.solado) $("p-solado").value = p.solado;
        $("p-preco").value = p.preco;
        $("p-promo").value = p.precoPromocional || "";
        $("p-descricao").value = p.descricao;
        $("p-imagens").value = d.imgs.join("\n");
        $("p-destaque").checked = p.destaque;
        $("form-produto").scrollIntoView({ behavior: "smooth" });
      } catch (err) { erro(err); }
    }
    if (remover && confirm("Desativar este produto? Ele sai da loja, mas o histórico de vendas é mantido.")) {
      try {
        await JB.api(`/api/admin/produtos/${remover.dataset.remover}`, { metodo: "DELETE", autenticado: true });
        JB.toast("Produto desativado.");
        carregarProdutos();
      } catch (err) { erro(err); }
    }
  });

  $("form-produto").addEventListener("submit", async e => {
    e.preventDefault();
    const imagens = $("p-imagens").value.split("\n").map(s => s.trim()).filter(Boolean);
    const corpo = {
      categoriaId: Number($("p-categoria").value),
      linha: $("p-linha").value,
      nome: $("p-nome").value.trim(),
      modelo: $("p-modelo").value.trim(),
      equipe: $("p-equipe").value.trim() || null,
      ano: $("p-ano").value ? Number($("p-ano").value) : null,
      marca: $("p-marca").value.trim() || null,
      solado: $("p-solado").value || null,
      preco: Number($("p-preco").value),
      precoPromocional: $("p-promo").value ? Number($("p-promo").value) : null,
      descricao: $("p-descricao").value.trim(),
      imagem: imagens[0] || "",
      destaque: $("p-destaque").checked,
      imagens
    };
    const id = $("produto-id").value;
    try {
      await JB.api(id ? `/api/admin/produtos/${id}` : "/api/admin/produtos", { metodo: id ? "PUT" : "POST", autenticado: true, corpo });
      JB.toast(id ? "Produto atualizado." : "Produto cadastrado. Abasteça o estoque na aba Estoque.");
      limparForm();
      carregarProdutos();
    } catch (err) { JB.aviso($("aviso-produto"), err.message); }
  });

  // ----------------------------------------------------- Banco de dados
  async function carregarConsultas() {
    if ($("lista-consultas").children.length) return;
    try {
      const lista = await JB.api("/api/admin/consultas", { autenticado: true });
      $("lista-consultas").innerHTML = lista.map(c =>
        `<button class="chip" data-consulta="${c.nome}" title="${JB.esc(c.descricao)}">${JB.esc(c.nome)}</button>`).join("");
      executarConsulta(lista[0].nome);
    } catch (e) { erro(e); }
  }
  $("lista-consultas").addEventListener("click", e => {
    const b = e.target.closest("[data-consulta]");
    if (b) executarConsulta(b.dataset.consulta);
  });

  async function executarConsulta(nome) {
    document.querySelectorAll("[data-consulta]").forEach(b => b.classList.toggle("ativo", b.dataset.consulta === nome));
    try {
      const r = await JB.api(`/api/admin/consultas/${encodeURIComponent(nome)}`, { autenticado: true });
      $("titulo-consulta").textContent = `${r.descricao} — ${r.linhas.length} linha(s)`;
      const fmt = v => v === null ? '<span class="texto-fraco">NULL</span>' : JB.esc(v);
      $("tabela-consulta").innerHTML =
        `<thead><tr>${r.colunas.map(c => `<th>${JB.esc(c)}</th>`).join("")}</tr></thead>
         <tbody>${r.linhas.map(l => `<tr>${r.colunas.map(c => `<td>${fmt(l[c])}</td>`).join("")}</tr>`).join("")}</tbody>`;
    } catch (e) { erro(e); }
  }

  // --------------------------------------------------- Moderação de avaliações
  async function carregarAvaliacoes() {
    const status = $("filtro-avaliacoes").value;
    const area = $("lista-moderacao");
    try {
      const lista = await JB.api(`/api/admin/avaliacoes${status ? "?status=" + status : ""}`, { autenticado: true });
      area.innerHTML = lista.length ? lista.map(a => `
        <article class="moderacao painel" data-id="${a.id}">
          <header>
            <span class="etiqueta ${a.status === "Publicada" ? "st-entregue" : a.status === "Oculta" ? "st-cancelado" : "st-pago"}">${JB.esc(a.status)}</span>
            <strong>${JB.esc(a.produto)}</strong>
            <span class="texto-suave">${JB.esc(a.cliente)} · ${JB.dataHora(a.data)} · ${a.nota}/5</span>
          </header>
          <p class="moderacao-texto">${a.comentario ? JB.esc(a.comentario) : '<span class="texto-fraco">(sem comentário)</span>'}</p>
          ${a.moderadoEm ? `<p class="texto-fraco moderacao-log">Moderada por ${JB.esc(a.moderador || "—")} em ${JB.dataHora(a.moderadoEm)}${a.motivoModeracao ? ` · motivo: ${JB.esc(a.motivoModeracao)}` : ""}</p>` : ""}
          <div class="moderacao-acoes">
            <label class="sr-only" for="motivo-${a.id}">Motivo para ocultar</label>
            <input id="motivo-${a.id}" class="entrada" maxlength="200" placeholder="Motivo (obrigatório para ocultar)">
            <button type="button" class="btn btn-contorno btn-pequeno" data-moderar="Publicada" ${a.status === "Publicada" ? "disabled" : ""}>Publicar</button>
            <button type="button" class="btn btn-perigo btn-pequeno" data-moderar="Oculta" ${a.status === "Oculta" ? "disabled" : ""}>Ocultar</button>
          </div>
        </article>`).join("")
        : '<p class="texto-suave">Nenhuma avaliação nesta situação.</p>';
    } catch (e) { erro(e); }
  }
  $("filtro-avaliacoes").addEventListener("change", carregarAvaliacoes);
  $("lista-moderacao").addEventListener("click", async e => {
    const b = e.target.closest("[data-moderar]");
    if (!b) return;
    const card = b.closest("[data-id]");
    const motivo = card.querySelector("input").value.trim();
    if (b.dataset.moderar === "Oculta" && !motivo) {
      card.querySelector("input").focus();
      return JB.toast("Informe o motivo para ocultar.", "erro");
    }
    b.disabled = true;
    try {
      await JB.api(`/api/admin/avaliacoes/${card.dataset.id}`, {
        metodo: "PUT", autenticado: true, corpo: { status: b.dataset.moderar, motivo: motivo || null }
      });
      JB.toast(b.dataset.moderar === "Oculta" ? "Avaliação ocultada." : "Avaliação publicada.");
      carregarAvaliacoes();
    } catch (err) { erro(err); b.disabled = false; }
  });

  // ------------------------------------------------------------ Acessos
  async function carregarAcessos() {
    try {
      const lista = await JB.api("/api/admin/acessos?limite=100", { autenticado: true });
      const falhas = lista.filter(a => !a.sucesso);
      const bloqueios = lista.filter(a => a.detalhe === "Conta bloqueada").length;
      const kpis = [
        ["Tentativas", lista.length, "últimos 100 registros"],
        ["Falhas", falhas.length, `${new Set(falhas.map(a => a.ip)).size} IP(s) diferentes`],
        ["Barradas pelo bloqueio", bloqueios, "conta bloqueada por 15 min"]
      ];
      $("kpis-acessos").innerHTML = kpis.map(([t, v, s]) => `<div class="kpi painel"><p>${t}</p><strong>${v}</strong><small>${s}</small></div>`).join("");
      $("tabela-acessos").innerHTML = lista.length
        ? lista.map(a => `<tr>
            <td>${JB.dataHora(a.data)}</td><td>${JB.esc(a.email)}</td><td>${JB.esc(a.ip || "—")}</td>
            <td><span class="etiqueta ${a.sucesso ? "st-entregue" : "st-cancelado"}">${a.sucesso ? "Sucesso" : "Falha"}</span></td>
            <td>${JB.esc(a.detalhe || "")}</td></tr>`).join("")
        : '<tr><td colspan="5" class="texto-suave">Nenhum acesso registrado.</td></tr>';
    } catch (e) { erro(e); }
  }

  abrir(carregadores[location.hash.slice(1)] ? location.hash.slice(1) : "visao");
})();
