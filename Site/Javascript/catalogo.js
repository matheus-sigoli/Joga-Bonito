// ============================================================================
// JOGA BONITO — catálogo com filtros (catalogo.js)
// Os filtros ficam na URL (?categoria=retro&linha=Clube) para poder compartilhar.
// ============================================================================

(() => {
  const form = document.getElementById("form-filtros");
  const resultado = document.getElementById("resultado");
  const resumo = document.getElementById("resumo-resultados");
  const precoMax = document.getElementById("preco-max");
  const titulos = {
    "": "Catálogo completo",
    "temporada-2026": "Temporada 2026",
    "retro": "Camisas Retrô",
    "chuteiras": "Chuteiras"
  };
  let produtos = [];

  // Estado inicial a partir da URL
  const url = new URLSearchParams(location.search);
  marcar("categoria", url.get("categoria") || "");
  marcar("linha", url.get("linha") || "");
  marcar("marca", url.get("marca") || "");
  if (url.get("ordem")) form.ordem.value = url.get("ordem");
  const busca = url.get("busca") || "";

  function marcar(nome, valor) {
    const el = form.querySelector(`input[name="${nome}"][value="${CSS.escape(valor)}"]`);
    if (el) el.checked = true;
  }

  function filtrosAtuais() {
    return {
      categoria: form.categoria.value,
      linha: form.linha.value,
      marca: form.categoria.value === "chuteiras" ? form.marca.value : "",
      ordem: form.ordem.value,
      busca
    };
  }

  /** Mostra apenas as linhas que combinam com a categoria escolhida. */
  function ajustarLinhas() {
    const cat = form.categoria.value;
    form.querySelectorAll("[data-grupo]").forEach(l => {
      const visivel = !cat || (cat === "chuteiras" ? l.dataset.grupo === "chuteira" : l.dataset.grupo === "camisa");
      l.hidden = !visivel;
      if (!visivel && l.querySelector("input").checked) marcar("linha", "");
    });
    // Marca só existe para chuteiras (planilha: Nike e adidas)
    const filtroMarca = document.getElementById("filtro-marca");
    filtroMarca.hidden = cat !== "chuteiras";
    if (filtroMarca.hidden) marcar("marca", "");
  }

  // Craque no topo do catálogo (Temporada: Mbappé · Retrô: Cristiano Ronaldo · todas: Lamine Yamal).
  // Leva à página de craques; se a foto ainda não estiver em IMG/Jogadores, o destaque não aparece.
  function mostrarCraque(categoria, termo) {
    const el = document.getElementById("catalogo-craque");
    const chave = termo ? null : { "temporada-2026": "mbappe", "retro": "cristiano-ronaldo", "": "lamine-yamal" }[categoria || ""];
    const c = chave && JB.craques.find(x => x.chave === chave);
    el.hidden = !c;
    if (!c) return;
    const img = el.querySelector("img");
    img.onerror = () => { el.hidden = true; };
    img.src = c.retrato || c.foto;
    img.alt = c.alt;
    img.style.setProperty("--foco", c.retrato ? "50% 20%" : c.foco);
    el.href = `craques.html#${c.chave}`;
    el.querySelector("strong").textContent = c.jogador;
    el.querySelector(".catalogo-craque-texto span").textContent = `${c.titulo} — craques que vestiram o manto`;
  }

  async function buscar() {
    ajustarLinhas();
    const f = filtrosAtuais();
    const qs = new URLSearchParams(Object.entries(f).filter(([, v]) => v));
    history.replaceState(null, "", `catalogo.html${qs.toString() ? "?" + qs : ""}`);

    const titulo = busca ? `Resultados para “${busca}”` : titulos[f.categoria] || "Catálogo";
    document.getElementById("titulo-catalogo").textContent = titulo;
    document.getElementById("trilha-atual").textContent = titulo;
    document.title = `${titulo} — Joga Bonito`;
    mostrarCraque(f.categoria, busca);

    resultado.innerHTML = Array.from({ length: 6 }, () => '<div class="esqueleto"></div>').join("");
    try {
      produtos = await JB.catalogo.listar(f);
      renderizar();
    } catch (e) {
      resultado.innerHTML = `<div class="vazio"><p>${JB.esc(e.message)}</p></div>`;
      resumo.textContent = "";
    }
  }

  /** Filtros locais (preço e disponibilidade) sem nova ida ao servidor. */
  function renderizar() {
    const max = Number(precoMax.value);
    const soDisponivel = document.getElementById("so-disponivel").checked;
    document.getElementById("preco-max-valor").textContent = `Até ${JB.brl(max)}`;

    const lista = produtos
      .filter(p => (p.precoFinal ?? p.preco) <= max)
      .filter(p => !soDisponivel || p.estoque > 0);

    resumo.textContent = `${lista.length} produto${lista.length === 1 ? "" : "s"} encontrado${lista.length === 1 ? "" : "s"}`;
    resultado.innerHTML = lista.length
      ? lista.map(JB.cardProduto).join("")
      : `<div class="vazio" style="grid-column:1/-1"><div class="icone-grande">0</div>
           <p>Nenhum produto com esses filtros.</p>
           <button class="btn btn-contorno btn-pequeno" data-clicar="#limpar-filtros">Limpar filtros</button></div>`;
  }

  form.addEventListener("change", e => {
    if (e.target === precoMax || e.target.id === "so-disponivel") renderizar();
    else buscar();
  });
  precoMax.addEventListener("input", renderizar);

  document.getElementById("limpar-filtros").addEventListener("click", () => {
    marcar("categoria", "");
    marcar("linha", "");
    marcar("marca", "");
    form.ordem.value = "relevancia";
    precoMax.value = precoMax.max;
    document.getElementById("so-disponivel").checked = false;
    if (busca) { location.href = "catalogo.html"; return; }
    buscar();
  });

  buscar();
})();
