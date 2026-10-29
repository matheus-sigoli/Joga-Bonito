// ============================================================================
// JOGA BONITO — layout comum (layout.js)
// Cabeçalho, rodapé, menu do usuário, barra de acessibilidade, VLibras e
// guia de medidas. Cada página só precisa de <div id="cabecalho"></div>
// e <div id="rodape"></div>.
// ============================================================================

// Ícones SVG (traço) — substituem emojis, herdam a cor do texto
const ICONES = {
  busca: '<svg class="icone" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/></svg>',
  carrinho: '<svg class="icone" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" aria-hidden="true"><path d="M3 4h2.5l2.2 11h10.6L20.5 7H6.4"/><circle cx="9.5" cy="19.5" r="1.5"/><circle cx="17" cy="19.5" r="1.5"/></svg>',
  menu: '<svg class="icone" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" aria-hidden="true"><path d="M3 6h18M3 12h18M3 18h18"/></svg>'
};

document.documentElement.classList.add("js");

(() => {
  const pagina = location.pathname.split("/").pop() || "inicial.html";
  const usuario = JB.sessao.usuario();

  // ------------------------------- Cabeçalho ---------------------------------
  const links = [
    ["catalogo.html?categoria=temporada-2026", "Temporada 2026"],
    ["catalogo.html?categoria=retro", "Retrô"],
    ["catalogo.html?categoria=chuteiras", "Chuteiras"],
    ["craques.html", "Craques"],
    ["catalogo.html", "Ver tudo"]
  ];

  const cab = document.getElementById("cabecalho");
  if (cab) {
    const iniciais = usuario
      ? usuario.nome.split(" ").filter(Boolean).slice(0, 2).map(p => p[0]).join("").toUpperCase()
      : "";
    const demo = window.JB_CONFIG && window.JB_CONFIG.modo === "demo";
    cab.outerHTML = `
      <a class="pular-conteudo" href="#conteudo">Pular para o conteúdo</a>
      ${demo ? `<div class="faixa-demo" role="note">
        <p><strong>Loja de demonstração</strong> · PIM IV UNIP 2026/2 — pagamentos simulados; seus dados ficam só neste navegador.</p>
        <button type="button" class="link-botao" id="recomecar-demo">Recomeçar a demonstração</button>
      </div>` : ""}
      <header class="topo">
        <div class="topo-principal">
          <button class="menu-btn" id="menu-btn" aria-label="Abrir menu" aria-expanded="false" aria-controls="menu-principal">${ICONES.menu}</button>
          <a href="inicial.html" class="logo" aria-label="Joga Bonito — página inicial">
            <img src="../IMG/LOGO 4.png" alt="Joga Bonito">
          </a>
          <nav class="menu" id="menu-principal" aria-label="Menu principal">
            ${links.map(([href, texto]) => `<a href="${href}"${location.href.endsWith(href) ? ' aria-current="page"' : ""}>${texto}</a>`).join("")}
          </nav>
          <form class="busca-topo" action="catalogo.html" role="search">
            <label for="busca-topo" class="sr-only">Buscar produtos</label>
            <input id="busca-topo" name="busca" type="search" placeholder="Buscar time, seleção ou ano…" autocomplete="off" spellcheck="false">
            <button type="submit" aria-label="Buscar">${ICONES.busca}</button>
          </form>
          <div class="topo-acoes">
            <a href="carrinho.html" class="acao-carrinho" aria-label="Carrinho">
              ${ICONES.carrinho}
              <span class="contador" id="contador-carrinho">0</span>
            </a>
            <div class="conta">
              ${usuario
                ? `<button class="avatar" id="avatar-btn" aria-haspopup="true" aria-expanded="false" aria-label="Minha conta">${JB.esc(iniciais)}</button>
                   <div class="conta-menu" id="conta-menu" hidden>
                     <p class="conta-nome">Olá, ${JB.esc(usuario.nome.split(" ")[0])}</p>
                     <a href="pedidos.html">Meus pedidos</a>
                     ${usuario.role === "Admin" ? '<a href="admin.html">Painel administrativo</a>' : ""}
                     <button type="button" id="sair-btn">Sair</button>
                   </div>`
                : `<a class="btn btn-contorno btn-pequeno" href="login.html">Entrar</a>`}
            </div>
          </div>
        </div>
      </header>`;

    const menuBtn = document.getElementById("menu-btn");
    const menu = document.getElementById("menu-principal");
    menuBtn?.addEventListener("click", () => {
      const aberto = menu.classList.toggle("aberto");
      menuBtn.setAttribute("aria-expanded", aberto);
    });

    const avatar = document.getElementById("avatar-btn");
    const contaMenu = document.getElementById("conta-menu");
    avatar?.addEventListener("click", e => {
      e.stopPropagation();
      contaMenu.hidden = !contaMenu.hidden;
      avatar.setAttribute("aria-expanded", !contaMenu.hidden);
    });
    document.addEventListener("click", () => { if (contaMenu) contaMenu.hidden = true; });
    document.getElementById("sair-btn")?.addEventListener("click", () => JB.sessao.sair());

    const busca = JB.parametro("busca");
    if (busca) document.getElementById("busca-topo").value = busca;
  }

  function atualizarContador() {
    const el = document.getElementById("contador-carrinho");
    if (el) {
      const qtd = JB.carrinho.quantidade();
      el.textContent = qtd;
      el.hidden = qtd === 0;
    }
  }
  atualizarContador();
  document.addEventListener("carrinho:mudou", atualizarContador);

  // -------------------------------- Rodapé -----------------------------------
  const rod = document.getElementById("rodape");
  if (rod) {
    rod.outerHTML = `
      <footer class="rodape">
        <div class="rodape-grade">
          <div>
            <h2>Joga Bonito</h2>
            <p>Camisas da Temporada 2026, clássicos retrô e chuteiras para campo, society e futsal. Cada peça é conferida antes de sair do estoque.</p>
          </div>
          <div>
            <h2>Loja</h2>
            <a href="catalogo.html?categoria=temporada-2026">Temporada 2026</a>
            <a href="catalogo.html?categoria=retro">Camisas Retrô</a>
            <a href="catalogo.html?categoria=chuteiras">Chuteiras</a>
            <a href="craques.html">Craques</a>
          </div>
          <div>
            <h2>Ajuda</h2>
            <a href="#" data-guia="camisa">Guia de medidas</a>
            <a href="inicial.html#duvidas">Trocas e prazos</a>
            <a href="privacidade.html">Privacidade (LGPD)</a>
          </div>
          <div>
            <h2>Pagamento</h2>
            <p>Pix · Cartão de crédito em até 6x sem juros · Cartão de débito</p>
          </div>
        </div>
        <svg class="rodape-marca" viewBox="0 0 1000 190" aria-hidden="true" focusable="false"><text x="0" y="172" textLength="1000" lengthAdjust="spacingAndGlyphs">JOGA BONITO</text></svg>
        <div class="rodape-academico"><div>
          <p>Loja fictícia criada para o PIM IV · Universidade Paulista (UNIP) · 2º semestre de 2026</p>
          <p>Matheus Sigoli · Caio Henrique · Antônio Roberto · Bernardo Rodrigues · Gustavo Henrico</p>
        </div></div>
      </footer>`;
  }

  // ------------------------ Barra de acessibilidade --------------------------
  const prefs = JB.ler("jb_acessibilidade", { contraste: false, fonte: 100 });
  function aplicarPrefs() {
    document.documentElement.classList.toggle("alto-contraste", !!prefs.contraste);
    document.documentElement.style.fontSize = `${prefs.fonte}%`;
    JB.gravar("jb_acessibilidade", prefs);
  }
  aplicarPrefs();

  const ICONE_CONTRASTE = '<svg class="icone" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 3a9 9 0 0 1 0 18Z" fill="currentColor"/></svg>';
  // Duas cópias da barra: no cabeçalho (telas largas) e dentro do menu (celular)
  function criarBarra(classeExtra) {
    const barra = document.createElement("div");
    barra.className = `acessibilidade ${classeExtra}`;
    barra.setAttribute("role", "toolbar");
    barra.setAttribute("aria-label", "Recursos de acessibilidade");
    barra.innerHTML = `
      <button type="button" data-acao="menos" aria-label="Diminuir fonte">A−</button>
      <button type="button" data-acao="mais" aria-label="Aumentar fonte">A+</button>
      <button type="button" data-acao="contraste" aria-label="Alto contraste" aria-pressed="${prefs.contraste}">${ICONE_CONTRASTE}</button>`;
    barra.addEventListener("click", e => {
      const acao = e.target.closest("button")?.dataset.acao;
      if (acao === "mais") prefs.fonte = Math.min(prefs.fonte + 10, 140);
      if (acao === "menos") prefs.fonte = Math.max(prefs.fonte - 10, 90);
      if (acao === "contraste") {
        prefs.contraste = !prefs.contraste;
        document.querySelectorAll('[data-acao="contraste"]').forEach(b => b.setAttribute("aria-pressed", prefs.contraste));
      }
      aplicarPrefs();
    });
    return barra;
  }
  document.querySelector(".topo-acoes")?.prepend(criarBarra("acess-topo"));
  document.getElementById("menu-principal")?.append(criarBarra("acess-menu"));

  // -------------------- VLibras (tradução para Libras) -----------------------
  // Em todas as páginas, inclusive o painel administrativo (funcionários surdos também administram a loja)
  {
    const vw = document.createElement("div");
    vw.setAttribute("vw", "");
    vw.className = "enabled";
    vw.innerHTML = `<div vw-access-button class="active"></div><div vw-plugin-wrapper><div class="vw-plugin-top-wrapper"></div></div>`;
    document.body.appendChild(vw);
    const s = document.createElement("script");
    s.src = "https://vlibras.gov.br/app/vlibras-plugin.js";
    s.onload = () => { try { new window.VLibras.Widget("https://vlibras.gov.br/app"); } catch { /* offline */ } };
    document.body.appendChild(s);
  }

  // ----------------------------- Guia de medidas -----------------------------
  const tabelas = {
    camisa: {
      titulo: "Guia de medidas — Camisas",
      dica: "Meça a largura da camisa que você mais gosta, de axila a axila, com ela esticada sobre uma mesa. Retrôs têm corte da época: se estiver entre dois tamanhos, escolha o maior.",
      cabecalho: ["Tamanho", "Largura (cm)", "Altura (cm)", "Veste peito (cm)"],
      linhas: [["P", "50", "70", "88 – 94"], ["M", "53", "72", "95 – 100"], ["G", "56", "74", "101 – 106"],
               ["GG", "59", "76", "107 – 112"], ["XG", "62", "78", "113 – 120"]]
    },
    chuteira: {
      titulo: "Guia de medidas — Chuteiras",
      dica: "Fique em pé sobre uma folha, marque o calcanhar e o dedo mais longo e meça. Chuteiras devem ficar justas: compre o seu número de tênis ou meio número abaixo se tiver o pé fino.",
      cabecalho: ["Número (BR)", "Comprimento do pé (cm)", "Equivalente EUA"],
      linhas: [["37", "24,0", "6"], ["38", "24,7", "7"], ["39", "25,3", "7,5"], ["40", "26,0", "8,5"],
               ["41", "26,7", "9"], ["42", "27,3", "10"], ["43", "28,0", "10,5"], ["44", "28,7", "11,5"]]
    }
  };

  function abrirGuia(tipo = "camisa") {
    const t = tabelas[tipo] || tabelas.camisa;
    let dialogo = document.getElementById("guia-medidas");
    if (!dialogo) {
      dialogo = document.createElement("dialog");
      dialogo.id = "guia-medidas";
      dialogo.className = "modal";
      document.body.appendChild(dialogo);
      dialogo.addEventListener("click", e => { if (e.target === dialogo) dialogo.close(); });
    }
    dialogo.innerHTML = `
      <div class="modal-caixa">
        <div class="modal-topo">
          <h2>${t.titulo}</h2>
          <button class="modal-fechar" aria-label="Fechar" data-fechar-dialogo>✕</button>
        </div>
        <div class="abas-guia">
          <button class="${tipo === "camisa" ? "ativa" : ""}" data-tipo="camisa">Camisas</button>
          <button class="${tipo === "chuteira" ? "ativa" : ""}" data-tipo="chuteira">Chuteiras</button>
        </div>
        <table class="tabela">
          <caption class="sr-only">${t.titulo}</caption>
          <thead><tr>${t.cabecalho.map(c => `<th scope="col">${c}</th>`).join("")}</tr></thead>
          <tbody>${t.linhas.map(l => `<tr>${l.map((c, i) => i === 0 ? `<th scope="row">${c}</th>` : `<td>${c}</td>`).join("")}</tr>`).join("")}</tbody>
        </table>
        <p class="dica">${t.dica}</p>
        <p class="dica">Não serviu? A primeira troca de tamanho é grátis em até 30 dias.</p>
      </div>`;
    dialogo.querySelectorAll(".abas-guia button").forEach(b =>
      b.addEventListener("click", () => abrirGuia(b.dataset.tipo)));
    if (!dialogo.open) dialogo.showModal();
  }
  JB.abrirGuiaMedidas = abrirGuia;
  JB.tabelasMedidas = tabelas;

  document.addEventListener("click", e => {
    const gatilho = e.target.closest("[data-guia]");
    if (gatilho) {
      e.preventDefault();
      abrirGuia(gatilho.dataset.guia);
    }
  });

  // ------------------------- Entradas ao rolar a página ----------------------
  // Cada filho marcado com .revelar sobe e aparece quando a seção entra na tela,
  // em sequência (60–90 ms entre um e outro). Sem script, nada fica escondido.
  function observarEntradas(raiz = document) {
    const itens = [...raiz.querySelectorAll(".revelar:not(.visivel)")];
    if (!("IntersectionObserver" in window)) { itens.forEach(i => i.classList.add("visivel")); return; }
    const obs = new IntersectionObserver(entradas => {
      entradas.forEach(e => {
        if (!e.isIntersecting) return;
        e.target.classList.add("visivel");
        obs.unobserve(e.target);
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
    itens.forEach(i => obs.observe(i));
  }
  JB.observarEntradas = observarEntradas;
  document.addEventListener("DOMContentLoaded", () => observarEntradas());
  if (document.readyState !== "loading") observarEntradas();
  // Conteúdo carregado depois (vitrines da API) também ganha a entrada
  new MutationObserver(() => observarEntradas()).observe(document.body, { childList: true, subtree: true });
})();

// Site público (modo demonstração): "Recomeçar" apaga só os dados deste navegador e recarrega a loja
document.addEventListener("click", e => {
  if (!e.target.closest("#recomecar-demo")) return;
  if (!confirm("Apagar contas criadas, pedidos e carrinho desta demonstração (só neste navegador)?")) return;
  ["jb_demo_loja_v1", "jb_demo_sessao", "jb_usuario", "jb_carrinho"].forEach(k => { try { localStorage.removeItem(k); } catch { /* ignore */ } });
  location.href = "inicial.html";
});
