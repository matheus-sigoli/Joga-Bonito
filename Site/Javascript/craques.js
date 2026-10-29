// ============================================================================
// JOGA BONITO — página de craques (craques.js)
// Os jogadores que vestiram o manto, cada um com a sua história e a camisa do time.
// ============================================================================
(async () => {
  const lista = document.getElementById("craques-completa");
  const indice = document.getElementById("craques-indice");
  indice.innerHTML = JB.craques.map(c =>
    `<li><a href="#${c.chave}"><strong>${JB.esc(c.jogador)}</strong><span>${JB.esc(c.time)} · ${JB.esc(c.ano)}</span></a></li>`).join("");

  let produtos = [];
  try { produtos = await JB.catalogo.listar(); } catch { /* sem a camisa à venda, a história continua */ }
  lista.innerHTML = JB.craques.map(c => JB.cardCraque(c, produtos.find(p => p.id === c.produtoId))).join("");
  lista.removeAttribute("aria-busy");

  // Chegou por um link "craques.html#kaka": rola até o craque depois de montar a lista
  if (location.hash) document.getElementById(location.hash.slice(1))?.scrollIntoView();
})();
