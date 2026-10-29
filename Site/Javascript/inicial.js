// ============================================================================
// JOGA BONITO — página inicial (inicial.js)
// Vitrines carregadas da API (Temporada com seleções x clubes), seletor
// "Qual chuteira é a sua?" e o movimento do número grande do topo.
// ============================================================================

const reduzMovimento = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

// -------------------------------- Vitrines ----------------------------------
async function carregarVitrine(grade, filtro) {
  const limite = Number(grade.dataset.limite) || 6;
  grade.setAttribute("aria-busy", "true");
  grade.innerHTML = Array.from({ length: Math.min(limite, 4) }, () => '<div class="esqueleto"></div>').join("");
  try {
    const produtos = await JB.catalogo.listar(filtro);
    grade.innerHTML = produtos.length
      ? produtos.slice(0, limite).map(JB.cardProduto).join("")
      : '<p class="vazio">Nenhum produto disponível no momento.</p>';
  } catch (e) {
    grade.innerHTML = `<p class="vazio">${JB.esc(e.message)}</p>`;
  } finally {
    grade.removeAttribute("aria-busy");
  }
}

(async () => {
  const grades = [...document.querySelectorAll("[data-categoria]")];
  await Promise.all(grades.map(g =>
    carregarVitrine(g, { categoria: g.dataset.categoria, linha: g.dataset.linha || "" })));
})();

// ------------------------- Vestiu o craque (jogadores) -------------------------
(async () => {
  const lista = document.getElementById("craques-lista");
  if (!lista) return;
  lista.innerHTML = JB.craques.map(JB.cardCraqueCompacto).join("");
})();

// ------------------ Temporada 2026: alternar seleções x clubes ------------------
document.querySelectorAll(".alternador").forEach(grupo => {
  const abas = [...grupo.querySelectorAll("[role=tab]")];
  const grade = document.getElementById(grupo.dataset.alvo);
  function escolher(aba, focar = false) {
    abas.forEach(a => {
      const ativa = a === aba;
      a.setAttribute("aria-selected", ativa);
      a.tabIndex = ativa ? 0 : -1;
    });
    if (focar) aba.focus();
    grade.setAttribute("aria-labelledby", aba.id);
    grade.dataset.linha = aba.dataset.linha;
    carregarVitrine(grade, { categoria: grade.dataset.categoria, linha: aba.dataset.linha });
  }
  abas.forEach((a, i) => {
    a.addEventListener("click", () => escolher(a));
    a.addEventListener("keydown", e => {
      const delta = { ArrowRight: 1, ArrowLeft: -1 }[e.key];
      if (!delta) return;
      e.preventDefault();
      escolher(abas[(i + delta + abas.length) % abas.length], true);
    });
  });
});

// --------------------- Seletor "Qual chuteira é a sua?" ---------------------
(() => {
  const pisos = {
    Campo: {
      onde: "Grama natural",
      travas: "Altas, cônicas ou em lâmina, que entram no gramado",
      evite: "Grama sintética e quadra: a trava alta prende e força o joelho",
      legenda: "Sola de campo: travas altas e cônicas"
    },
    Society: {
      onde: "Grama sintética (society e fut7)",
      travas: "Muitas travas baixas de borracha, que espalham o peso",
      evite: "Gramado natural molhado (escorrega) e quadra lisa",
      legenda: "Sola society: dezenas de travas baixas de borracha"
    },
    Futsal: {
      onde: "Quadra, salão e piso de madeira",
      travas: "Nenhuma: sola lisa de borracha que não marca o piso, com ponto de giro",
      evite: "Grama de qualquer tipo: sem travas, não há tração",
      legenda: "Sola de futsal: borracha lisa com círculo de giro"
    }
  };
  const abas = [...document.querySelectorAll(".piso-escolha:not(.alternador) [role=tab]")];
  const grade = document.getElementById("grade-piso");
  const sola = document.getElementById("sola-atual");
  if (!abas.length) return;

  function escolher(linha, focar = false) {
    const p = pisos[linha];
    abas.forEach(a => {
      const ativa = a.dataset.linha === linha;
      a.setAttribute("aria-selected", ativa);
      a.tabIndex = ativa ? 0 : -1;
      if (ativa && focar) a.focus();
    });
    document.getElementById("piso-nome").textContent = linha;
    document.getElementById("piso-onde").textContent = p.onde;
    document.getElementById("piso-travas").textContent = p.travas;
    document.getElementById("piso-evite").textContent = p.evite;
    document.getElementById("sola-legenda").textContent = p.legenda;
    const link = document.getElementById("piso-link");
    link.href = `catalogo.html?categoria=chuteiras&linha=${linha}`;
    link.textContent = `Ver todas de ${linha.toLowerCase()}`;
    sola.classList.remove("trocando");
    void sola.offsetWidth; // reinicia a animação de troca
    sola.querySelector("use").setAttribute("href", `#sola-${linha.toLowerCase()}`);
    sola.classList.add("trocando");
    grade.dataset.limite = 2;
    carregarVitrine(grade, { categoria: "chuteiras", linha });
  }

  abas.forEach((a, i) => {
    a.addEventListener("click", () => escolher(a.dataset.linha));
    // Setas do teclado entre as abas (padrão WAI-ARIA)
    a.addEventListener("keydown", e => {
      const delta = { ArrowRight: 1, ArrowLeft: -1 }[e.key];
      if (!delta) return;
      e.preventDefault();
      escolher(abas[(i + delta + abas.length) % abas.length].dataset.linha, true);
    });
  });
  escolher("Campo");
})();

// --------------- Números grandes acompanham a rolagem (parallax) ---------------
(() => {
  if (reduzMovimento) return;
  const alvos = [
    [document.querySelector(".hero-numero"), -0.18],
  ].filter(([el]) => el);
  let agendado = false;
  function atualizar() {
    agendado = false;
    const meio = innerHeight / 2;
    alvos.forEach(([el, fator]) => {
      const r = el.parentElement.getBoundingClientRect();
      const desloc = (r.top + r.height / 2 - meio) * fator;
      el.style.transform = `translate3d(0, ${desloc.toFixed(1)}px, 0)`;
    });
  }
  addEventListener("scroll", () => { if (!agendado) { agendado = true; requestAnimationFrame(atualizar); } }, { passive: true });
  atualizar();
})();

// Volta da exclusão de conta (LGPD)
if (new URLSearchParams(location.search).get("conta") === "excluida")
  JB.toast("Sua conta foi excluída e seus dados pessoais foram removidos.");
