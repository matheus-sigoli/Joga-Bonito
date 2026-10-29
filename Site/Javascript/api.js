// ============================================================================
// JOGA BONITO — núcleo do front-end (api.js)
// Cliente da API REST, sessão JWT, carrinho, formatação e utilidades.
// Carregado em todas as páginas antes dos scripts específicos.
// ============================================================================

const JB = (() => {
  // ---------------------------------------------------------------------------
  // Endereço da API (ver config.js):
  //   1. JB_CONFIG.apiBase definido → usa esse endereço;
  //   2. site aberto no próprio computador fora da API (Live Server, arquivo) →
  //      http://localhost:5000 — só faz sentido em desenvolvimento;
  //   3. qualquer outro caso (API servindo o site, local ou publicado) → mesma origem.
  // Assim o site publicado nunca tenta acessar o "localhost" do visitante.
  // ---------------------------------------------------------------------------
  const CONFIGURADO = window.JB_CONFIG && typeof window.JB_CONFIG.apiBase === "string";
  // Página aberta FORA da API: arquivo (dois cliques), Live Server (127.0.0.1:5500) ou outra porta local
  // Site público (modo demonstração): a "API" é o motor loja-demo.js, na própria página
  const DEMO = !!(window.JB_CONFIG && window.JB_CONFIG.modo === "demo");
  const FORA_DA_API = !CONFIGURADO && !DEMO && (window.location.protocol === "file:" ||
    (["localhost", "127.0.0.1", "[::1]"].includes(window.location.hostname) && window.location.port !== "5000"));
  const API_BASE = (() => {
    if (CONFIGURADO) return window.JB_CONFIG.apiBase.replace(/\/+$/, "");
    if (!FORA_DA_API) return "";
    // Mesmo nome de host da página: 127.0.0.1 com 127.0.0.1, localhost com localhost.
    // Para o navegador são sites diferentes, e o cookie de sessão (SameSite=Strict) não passaria de um para o outro.
    const host = window.location.hostname === "127.0.0.1" ? "127.0.0.1" : "localhost";
    return `http://${host}:5000`;
  })();
  // A loja servida pela própria API é o jeito garantido de o login funcionar: se a API estiver no ar,
  // a página é reaberta por ela (mesma página, mesmos parâmetros) antes de qualquer coisa.
  // O nome do host é mantido (127.0.0.1 continua 127.0.0.1): o cookie de sessão vale por host.
  // "jbsessao=1" avisa a página de destino que há sessão no cookie, para ela recuperar o usuário.
  function abrirNaApi(pagina = location.pathname.split("/").pop() || "inicial.html", comSessao = false) {
    const url = new URL(`${API_BASE}/HTML/${pagina}`);
    if (pagina === (location.pathname.split("/").pop() || "inicial.html")) {
      new URLSearchParams(location.search).forEach((v, k) => url.searchParams.set(k, v));
      url.hash = location.hash;
    }
    let temSessao = comSessao;
    try { temSessao = temSessao || !!localStorage.getItem("jb_usuario"); } catch { /* modo privado */ }
    if (temSessao) url.searchParams.set("jbsessao", "1");
    window.location.replace(url.toString());
  }
  if (FORA_DA_API) {
    fetch(`${API_BASE}/health/live`, { cache: "no-store", mode: "no-cors" }).then(() => abrirNaApi(), () => {});
  }
  const CHAVE_USUARIO = "jb_usuario";
  const CHAVE_CARRINHO = "jb_carrinho";
  const LIMITE_FRETE_GRATIS = 299;
  const VALOR_FRETE = 19.9;

  // ------------------------------ Armazenamento ------------------------------
  function ler(chave, padrao = null) {
    try {
      const v = localStorage.getItem(chave);
      return v === null ? padrao : JSON.parse(v);
    } catch {
      return padrao;
    }
  }
  function gravar(chave, valor) {
    try { localStorage.setItem(chave, JSON.stringify(valor)); } catch { /* modo privado */ }
  }
  function remover(chave) {
    try { localStorage.removeItem(chave); } catch { /* ignore */ }
  }

  // --------------------------------- Sessão ----------------------------------
  // O token NÃO fica no navegador ao alcance do JavaScript: a API o grava num cookie HttpOnly
  // (SameSite=Strict). Aqui guardamos só nome, perfil e validade, para montar o menu.
  remover("jb_token"); // versões anteriores guardavam o token aqui
  const sessao = {
    usuario: () => ler(CHAVE_USUARIO),
    logado: () => !!ler(CHAVE_USUARIO),
    ehAdmin: () => (ler(CHAVE_USUARIO) || {}).role === "Admin",
    salvar(resposta) {
      gravar(CHAVE_USUARIO, { ...resposta.usuario, expiraEm: resposta.expiraEm });
    },
    sair(redirecionar = true) {
      const tinhaSessao = !!ler(CHAVE_USUARIO);
      remover(CHAVE_USUARIO);
      // Apaga o cookie no servidor; keepalive deixa a requisição terminar mesmo trocando de página
      if (tinhaSessao) {
        fetch(API_BASE + "/api/auth/sair", {
          method: "POST", credentials: "include", keepalive: true, headers: { "X-JB-Requisicao": "1" }
        }).catch(() => {});
      }
      if (redirecionar) window.location.href = "inicial.html";
    },
    expirada() {
      const u = ler(CHAVE_USUARIO);
      return !!u && !!u.expiraEm && new Date(u.expiraEm) < new Date();
    }
  };
  if (sessao.expirada()) sessao.sair(false);

  // Chegou de outra origem (Live Server/arquivo) com sessão no cookie: recupera nome e perfil e recarrega limpo
  (() => {
    const params = new URLSearchParams(location.search);
    if (!params.has("jbsessao")) return;
    params.delete("jbsessao");
    const limpa = location.pathname + (params.toString() ? `?${params}` : "") + location.hash;
    if (sessao.logado()) { history.replaceState(null, "", limpa); return; }
    fetch(`${API_BASE}/api/auth/me`, { credentials: "include", headers: { Accept: "application/json" } })
      .then(r => (r.ok ? r.json() : null))
      .then(u => { if (u) gravar(CHAVE_USUARIO, { ...u, expiraEm: null }); })
      .catch(() => {})
      .finally(() => window.location.replace(limpa));
  })();

  /** Exige login; volta para a página atual depois de entrar. */
  function exigirLogin() {
    if (sessao.logado()) return true;
    const volta = encodeURIComponent(location.pathname.split("/").pop() + location.search);
    window.location.href = `login.html?volta=${volta}`;
    return false;
  }

  // ------------------------------ Requisições --------------------------------
  class ErroApi extends Error {
    constructor(mensagem, status) {
      super(mensagem);
      this.status = status;
    }
  }

  async function api(caminho, { metodo = "GET", corpo, autenticado = false, timeout = 10000 } = {}) {
    // X-JB-Requisicao: prova de que a chamada saiu do próprio site (proteção CSRF na API)
    // X-JB-Cliente: o login devolve a sessão em cookie HttpOnly, não no corpo
    const headers = { Accept: "application/json", "X-JB-Requisicao": "1", "X-JB-Cliente": "web" };
    if (corpo !== undefined) headers["Content-Type"] = "application/json";
    const logado = sessao.logado();
    if (autenticado && !logado) throw new ErroApi("Faça login para continuar.", 401);

    const controle = new AbortController();
    const timer = setTimeout(() => controle.abort(), timeout);
    let resposta;
    try {
      resposta = await fetch(API_BASE + caminho, {
        method: metodo,
        headers,
        credentials: "include",
        body: corpo !== undefined ? JSON.stringify(corpo) : undefined,
        signal: controle.signal
      });
    } catch {
      throw new ErroApi("A loja está reconectando ao servidor. Tente de novo em alguns segundos.", 0);
    } finally {
      clearTimeout(timer);
    }

    if (resposta.status === 204) return null;
    let dados = null;
    try { dados = await resposta.json(); } catch { /* sem corpo */ }

    if (!resposta.ok) {
      if (resposta.status === 401 && logado) {
        // Token expirado, senha trocada em outro aparelho ou conta desativada: a API diz o motivo
        sessao.sair(false);
        throw new ErroApi((dados && dados.mensagem) || "Sua sessão expirou. Entre novamente.", 401);
      }
      const padrao = {
        401: "Faça login para continuar.",
        403: "Você não tem permissão para esta ação.",
        404: "Não encontrado.",
        429: "Muitas tentativas. Aguarde um minuto e tente de novo."
      }[resposta.status] || "Erro ao processar a solicitação.";
      throw new ErroApi((dados && (dados.mensagem || dados.title)) || padrao, resposta.status);
    }
    return dados;
  }

  // ------------------------------- Carrinho ----------------------------------
  // Item: { id, nome, img, preco, tamanho, qtd, linha }
  const carrinho = {
    itens: () => ler(CHAVE_CARRINHO, []),
    salvar(itens) {
      gravar(CHAVE_CARRINHO, itens);
      document.dispatchEvent(new CustomEvent("carrinho:mudou"));
    },
    adicionar(produto, tamanho, qtd) {
      const itens = carrinho.itens();
      const existente = itens.find(i => i.id === produto.id && i.tamanho === tamanho);
      if (existente) existente.qtd = Math.min(existente.qtd + qtd, 10);
      else itens.push({
        id: produto.id, nome: produto.nome, img: produto.img, preco: produto.precoFinal ?? produto.preco,
        tamanho, qtd: Math.min(qtd, 10), linha: produto.linha
      });
      carrinho.salvar(itens);
    },
    alterar(id, tamanho, qtd) {
      let itens = carrinho.itens();
      if (qtd <= 0) itens = itens.filter(i => !(i.id === id && i.tamanho === tamanho));
      else itens.forEach(i => { if (i.id === id && i.tamanho === tamanho) i.qtd = Math.min(qtd, 10); });
      carrinho.salvar(itens);
    },
    limpar: () => carrinho.salvar([]),
    quantidade: () => carrinho.itens().reduce((s, i) => s + i.qtd, 0),
    subtotal: () => carrinho.itens().reduce((s, i) => s + i.preco * i.qtd, 0),
    paraApi: () => carrinho.itens().map(i => ({ produtoId: i.id, tamanho: i.tamanho, quantidade: i.qtd }))
  };

  // ------------------------------- Formatação --------------------------------
  const moeda = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
  const brl = v => moeda.format(Number(v) || 0);
  const data = v => new Date(v).toLocaleDateString("pt-BR");
  const dataHora = v => new Date(v).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });

  /** Escapa HTML para evitar XSS ao montar conteúdo vindo da API. */
  function esc(texto) {
    return String(texto ?? "").replace(/[&<>"']/g, c => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
    })[c]);
  }

  function estrelas(nota) {
    const n = Math.round(Number(nota) || 0);
    return `<span class="estrelas" aria-label="Nota ${Number(nota || 0).toFixed(1)} de 5">${"★".repeat(n)}${"☆".repeat(5 - n)}</span>`;
  }

  function parametro(nome) {
    return new URLSearchParams(window.location.search).get(nome);
  }

  // --------------------------------- Avisos ----------------------------------
  function toast(mensagem, tipo = "sucesso") {
    let area = document.getElementById("toasts");
    if (!area) {
      area = document.createElement("div");
      area.id = "toasts";
      area.className = "toasts";
      area.setAttribute("role", "status");
      area.setAttribute("aria-live", "polite");
      document.body.appendChild(area);
    }
    const el = document.createElement("div");
    el.className = `toast toast-${tipo}`;
    el.textContent = mensagem;
    area.appendChild(el);
    setTimeout(() => el.classList.add("saindo"), 3200);
    setTimeout(() => el.remove(), 3700);
  }

  /** Mostra uma mensagem dentro de um elemento (formulários). */
  function aviso(elemento, mensagem, tipo = "erro") {
    if (!elemento) return;
    elemento.className = `aviso aviso-${tipo}`;
    elemento.textContent = mensagem;
    elemento.hidden = !mensagem;
  }

  /** Card de produto padrão (home, catálogo, recomendados). */
  function cardProduto(p, i = 0) {
    const promo = p.precoPromocional && p.precoPromocional < p.preco;
    const esgotado = p.estoque === 0;
    return `
      <article class="card-produto revelar${esgotado ? " esgotado" : ""}" style="--atraso:${(i % 4) * 70}ms">
        <a href="Produtos.html?id=${p.id}" class="card-link" aria-label="${esc(p.nome)}">
          <div class="card-img">
            <img src="${esc(p.img)}" alt="${esc(p.nome)}" loading="lazy" width="480" height="480" data-fallback="logo">
            <div class="selos">
              ${promo ? `<span class="selo selo-promo">−${Math.round((1 - p.precoPromocional / p.preco) * 100)}%</span>` : ""}
              ${esgotado ? `<span class="selo selo-esgotado">Esgotado</span>` : ""}
            </div>
          </div>
          <div class="card-corpo">
            <p class="card-modelo">${esc(rotuloProduto(p))}</p>
            <h3 class="card-titulo">${esc(p.nome)}</h3>
            ${p.totalAvaliacoes > 0 ? `<p class="card-nota">${estrelas(p.notaMedia)} <span>(${p.totalAvaliacoes})</span></p>` : ""}
            <p class="card-preco">
              ${promo ? `<s>${brl(p.preco)}</s>` : ""}
              <strong>${brl(p.precoFinal ?? p.preco)}</strong>
            </p>
            <p class="card-parcela">ou 6x de ${brl((p.precoFinal ?? p.preco) / 6)} sem juros</p>
          </div>
        </a>
      </article>`;
  }

  // ------------------------------- Conexão ------------------------------------
  // Quando a API não responde, a vitrine usa o catálogo salvo (catalogo-local.js) e esta
  // faixa avisa que a loja está reconectando. A cada poucos segundos a API é testada de novo;
  // quando volta, a página recarrega sozinha com os dados do banco — sem o cliente fazer nada.
  const conexao = (() => {
    let monitorando = false;
    let espera = 3000;
    async function apiNoAr() {
      // no-cors: basta o servidor responder (funciona até com a página aberta como arquivo)
      try {
        await fetch(`${API_BASE || ""}/health/live`, { cache: "no-store", mode: "no-cors" });
        return true;
      } catch { return false; }
    }
    function faixa() {
      let area = document.getElementById("aviso-offline-area");
      if (!area) {
        area = document.createElement("div");
        area.id = "aviso-offline-area";
        document.querySelector("main")?.prepend(area);
      }
      if (area.querySelector(".aviso-offline")) return;
      area.innerHTML = `
        <div class="aviso-offline" role="status" aria-live="polite">
          <span class="aviso-offline-ponto" aria-hidden="true"></span>
          <p><strong>Reconectando à loja.</strong> Você pode navegar pelo catálogo salvo; preços e estoque são
          confirmados assim que o servidor responder — a página se atualiza sozinha.</p>
          <button type="button" class="btn btn-contorno btn-pequeno" id="tentar-conexao">Tentar agora</button>
        </div>`;
      document.getElementById("tentar-conexao").addEventListener("click", verificar);
    }
    async function verificar() {
      if (await apiNoAr()) { window.location.reload(); return; }
      espera = Math.min(espera * 1.5, 15000);
      setTimeout(verificar, espera);
    }
    /**
     * Executa uma chamada; se a API ainda estiver ligando (sem resposta), espera até 90 s e tenta de novo
     * sozinha — o cliente não precisa clicar outra vez. aoEsperar(mensagem) mostra o andamento.
     */
    async function quandoNoAr(acao, aoEsperar = () => {}) {
      try { return await acao(); } catch (e) { if (e.status !== 0) throw e; }
      aoEsperar("Ligando a loja… você entra assim que o servidor responder (até 1 minuto).");
      const limite = Date.now() + 90000;
      while (Date.now() < limite) {
        await new Promise(r => setTimeout(r, 3000));
        if (await apiNoAr()) {
          try { return await acao(); } catch (e) { if (e.status !== 0) throw e; }
        }
      }
      throw new ErroApi("A loja não respondeu. Abra o atalho Joga Bonito na área de trabalho (ou iniciar-projeto.bat) e tente de novo.", 0);
    }

    /** Erro 5xx: pergunta ao health check o motivo (em desenvolvimento ele diz qual conexão falhou). */
    async function explicarFalha() {
      try {
        const r = await fetch(`${API_BASE}/health/ready`, { cache: "no-store", credentials: "include" });
        const d = await r.json();
        const ruim = (d.componentes || []).find(c => c.status !== "Healthy");
        if (ruim) return `O servidor está no ar, mas o banco de dados não respondeu: ${ruim.descricao || ruim.nome}. ` +
          "No computador da loja, rode iniciar-projeto.bat para ligar o SQL Server.";
        if (d.status && d.status !== "Healthy") return "O servidor está no ar, mas o banco de dados ainda está sendo preparado. Tente em alguns segundos.";
      } catch { /* sem detalhes */ }
      return null;
    }

    return {
      apiNoAr, quandoNoAr, explicarFalha,
      offline() {
        faixa();
        if (monitorando) return;
        monitorando = true;
        setTimeout(verificar, espera);
      }
    };
  })();

  /** "Nike · TF — society" para chuteiras; "Clube · Flamengo 1981" para camisas. */
  function rotuloProduto(p) {
    if (p.marca) return p.solado ? `${p.marca} · ${p.solado}` : p.marca;
    if (p.equipe) return `${p.linha} · ${p.equipe}${p.ano ? " " + p.ano : ""}`;
    return p.modelo;
  }

  return {
    API_BASE, LIMITE_FRETE_GRATIS, VALOR_FRETE, rotuloProduto,
    api, ErroApi, sessao, exigirLogin, carrinho, conexao, FORA_DA_API, abrirNaApi,
    brl, data, dataHora, esc, estrelas, parametro, toast, aviso, cardProduto,
    ler, gravar
  };
})();

// ----------------------------------------------------------------------------
// Comportamentos declarativos (sem onclick/onerror inline — exigência da CSP)
//   <img data-fallback="logo">            troca por logo se a imagem falhar
//   <img data-fallback="remover-botao">   remove a miniatura que falhou
//   <button data-fechar-dialogo>          fecha o <dialog> em que está
//   <button data-clicar="#seletor">       aciona outro botão da página
// ----------------------------------------------------------------------------
document.addEventListener("error", e => {
  const img = e.target;
  if (!(img instanceof HTMLImageElement) || !img.dataset.fallback) return;
  if (img.dataset.fallback === "remover-botao") { img.closest("button")?.remove(); return; }
  if (img.dataset.fallback === "craque") {
    // Foto do craque ainda não colocada em IMG/Jogadores: cartão com número, nome e cores do time
    const cartao = document.createElement("div");
    cartao.className = `${img.className} craque-cartao`;
    cartao.setAttribute("role", "img");
    cartao.setAttribute("aria-label", `${img.dataset.nome} — ${img.dataset.time}`);
    cartao.style.setProperty("--c1", img.dataset.cor1 || "#16733A");
    cartao.style.setProperty("--c2", img.dataset.cor2 || "#FCCA0F");
    for (const [classe, texto] of [["craque-cartao-numero", img.dataset.numero], ["craque-cartao-nome", img.dataset.nome],
                                   ["craque-cartao-time", img.dataset.time]]) {
      const el = document.createElement("span");
      el.className = classe;
      el.textContent = texto || "";
      cartao.appendChild(el);
    }
    img.replaceWith(cartao);
    return;
  }
  if (img.dataset.falhou) return; // evita laço se o próprio logo falhar
  img.dataset.falhou = "1";
  img.classList.add("img-falha");
  img.src = "../IMG/LOGO 2.png";
}, true); // "error" não borbulha: captura

document.addEventListener("click", e => {
  const fechar = e.target.closest("[data-fechar-dialogo]");
  if (fechar) { fechar.closest("dialog")?.close(); return; }
  const alvo = e.target.closest("[data-clicar]");
  if (alvo) document.querySelector(alvo.dataset.clicar)?.click();
});
