// ============================================================================
// JOGA BONITO — histórico de pedidos (pedidos.js)
// Linha do tempo vinda da tabela HistoricoStatusPedido (gravada por trigger).
// ============================================================================

(async () => {
  if (!JB.exigirLogin()) return;
  const lista = document.getElementById("lista-pedidos");
  const etapas = ["Pago", "Em Separação", "Enviado", "Entregue"];
  const classe = s => "st-" + s.toLowerCase().replace(/\s+/g, "-");

  async function carregar() {
    lista.innerHTML = '<div class="esqueleto" style="min-height:180px;margin-top:20px"></div>';
    let pedidos;
    try {
      pedidos = await JB.api("/api/pedidos/meus", { autenticado: true });
    } catch (e) {
      lista.innerHTML = `<div class="vazio"><p>${JB.esc(e.message)}</p></div>`;
      return;
    }

    if (!pedidos.length) {
      lista.innerHTML = `<div class="vazio painel"><div class="icone-grande">0</div><p>Você ainda não fez nenhum pedido.</p>
        <p><a href="catalogo.html" class="btn btn-primario">Começar a comprar</a></p></div>`;
      return;
    }

    lista.innerHTML = pedidos.map(p => {
      const cancelado = p.status === "Cancelado";
      const idxAtual = etapas.indexOf(p.status);
      const dataEtapa = s => p.historico.find(h => h.status === s)?.data;
      return `
      <article class="pedido painel">
        <header class="pedido-topo">
          <div>
            <h2>Pedido #${p.id}</h2>
            <p class="texto-suave">${JB.dataHora(p.data)} · ${JB.esc(p.formaPagamento)}${p.parcelas > 1 ? ` em ${p.parcelas}x` : ""} · via ${JB.esc(p.origem)}</p>
          </div>
          <span class="etiqueta ${classe(p.status)}">${JB.esc(p.status)}</span>
        </header>

        ${cancelado
          ? `<p class="aviso aviso-erro">Pedido cancelado em ${JB.dataHora(dataEtapa("Cancelado") || p.data)}. As peças voltaram ao estoque e o valor será estornado.</p>`
          : `<ol class="linha-tempo" aria-label="Andamento do pedido">
              ${etapas.map((s, i) => `
                <li class="${i <= idxAtual ? "feito" : ""}${i === idxAtual ? " atual" : ""}">
                  <span class="marco" aria-hidden="true">${i <= idxAtual ? "✓" : i + 1}</span>
                  <span>${s}</span>
                  <small>${dataEtapa(s) ? JB.dataHora(dataEtapa(s)) : ""}</small>
                </li>`).join("")}
            </ol>`}

        <div class="pedido-itens">
          ${p.itens.map(i => `
            <div class="pedido-item">
              <img src="${JB.esc(i.img)}" alt="" data-fallback="logo">
              <div>
                <a href="Produtos.html?id=${i.produtoId}${p.status === "Entregue" ? "#avaliacoes" : ""}">${JB.esc(i.nome)}</a>
                <p class="texto-suave">Tam. ${JB.esc(i.tamanho)} · ${i.qtd} × ${JB.brl(i.preco)}</p>
              </div>
              <strong>${JB.brl(i.subtotal)}</strong>
            </div>`).join("")}
        </div>

        <footer class="pedido-rodape">
          <div class="texto-suave">
            ${p.codigoRastreio ? `Rastreio: <strong class="rastreio">${JB.esc(p.codigoRastreio)}</strong>` : ""}
          </div>
          <dl class="valores valores-pedido">
            <div><dt>Subtotal</dt><dd>${JB.brl(p.subtotal)}</dd></div>
            ${p.desconto > 0 ? `<div><dt>Desconto</dt><dd class="positivo">− ${JB.brl(p.desconto)}</dd></div>` : ""}
            <div><dt>Frete</dt><dd>${p.frete > 0 ? JB.brl(p.frete) : "Grátis"}</dd></div>
            <div class="total"><dt>Total</dt><dd>${JB.brl(p.total)}</dd></div>
          </dl>
        </footer>
        ${["Pago", "Aguardando Pagamento"].includes(p.status)
          ? `<button class="btn btn-perigo btn-pequeno" data-cancelar="${p.id}">Cancelar pedido</button>` : ""}
        ${p.status === "Entregue" ? `<p class="texto-suave">Gostou? <a href="Produtos.html?id=${p.itens[0]?.produtoId}#avaliacoes">Avalie os produtos</a> e ajude outros torcedores.</p>` : ""}
      </article>`;
    }).join("");
  }

  lista.addEventListener("click", async e => {
    const b = e.target.closest("[data-cancelar]");
    if (!b) return;
    if (!confirm(`Cancelar o pedido #${b.dataset.cancelar}? As peças voltam para o estoque.`)) return;
    b.disabled = true;
    try {
      await JB.api(`/api/pedidos/${b.dataset.cancelar}/cancelar`, { metodo: "POST", autenticado: true });
      JB.toast("Pedido cancelado.");
      carregar();
    } catch (err) {
      JB.toast(err.message, "erro");
      b.disabled = false;
    }
  });

  carregar();
})();

// ---------------------------------------------------------------------------
// Trocar senha (POST /api/auth/trocar-senha — exige a senha atual)
// ---------------------------------------------------------------------------
(() => {
  const form = document.getElementById("form-senha");
  if (!form || !JB.sessao.logado()) return;
  const aviso = document.getElementById("aviso-senha");
  form.addEventListener("submit", async e => {
    e.preventDefault();
    const atual = form.querySelector("#senha-atual").value;
    const nova = form.querySelector("#senha-nova").value;
    const confirma = form.querySelector("#senha-confirma").value;
    if (!atual || !nova) return JB.aviso(aviso, "Preencha a senha atual e a nova senha.");
    if (nova !== confirma) return JB.aviso(aviso, "A confirmação não é igual à nova senha.");
    const botao = form.querySelector("button[type=submit]");
    botao.disabled = true;
    try {
      // A API encerra as outras sessões e devolve um token novo para esta continuar logada
      const sessaoNova = await JB.api("/api/auth/trocar-senha", { metodo: "POST", autenticado: true, corpo: { senhaAtual: atual, novaSenha: nova } });
      JB.sessao.salvar(sessaoNova);
      form.reset();
      JB.aviso(aviso, "");
      JB.toast("Senha alterada.");
      document.getElementById("conta-senha").open = false;
    } catch (err) {
      JB.aviso(aviso, err.message);
    } finally {
      botao.disabled = false;
    }
  });

  document.getElementById("sair-todos").addEventListener("click", async () => {
    if (!confirm("Encerrar a sessão em todos os aparelhos, inclusive neste?")) return;
    try {
      await JB.api("/api/auth/sair-de-todos", { metodo: "POST", autenticado: true });
      JB.sessao.sair();
    } catch (err) {
      JB.toast(err.message, "erro");
    }
  });
})();

// ---------------------------------------------------------------------------
// LGPD: baixar os dados (GET /api/auth/meus-dados) e excluir a conta
// ---------------------------------------------------------------------------
(() => {
  if (!JB.sessao.logado()) return;
  if (location.hash === "#conta-dados") document.getElementById("conta-dados").open = true;

  document.getElementById("baixar-dados").addEventListener("click", async e => {
    const botao = e.currentTarget;
    botao.disabled = true;
    try {
      const dados = await JB.api("/api/auth/meus-dados", { autenticado: true });
      const arquivo = new Blob([JSON.stringify(dados, null, 2)], { type: "application/json" });
      const link = document.createElement("a");
      link.href = URL.createObjectURL(arquivo);
      link.download = `meus-dados-jogabonito-${new Date().toISOString().slice(0, 10)}.json`;
      document.body.appendChild(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(link.href), 1000);
      JB.toast("Arquivo com os seus dados baixado.");
    } catch (err) {
      JB.toast(err.message, "erro");
    } finally {
      botao.disabled = false;
    }
  });

  document.getElementById("form-excluir").addEventListener("submit", async e => {
    e.preventDefault();
    const aviso = document.getElementById("aviso-exclusao");
    const senha = document.getElementById("senha-exclusao").value;
    if (!senha) return JB.aviso(aviso, "Digite sua senha para confirmar.");
    if (!confirm("Excluir a conta de vez? Esta ação não pode ser desfeita.")) return;
    try {
      await JB.api("/api/auth/excluir-conta", { metodo: "POST", autenticado: true, corpo: { senha } });
      JB.carrinho.limpar();
      JB.sessao.sair(false);
      location.href = "inicial.html?conta=excluida";
    } catch (err) {
      JB.aviso(aviso, err.message);
    }
  });
})();
