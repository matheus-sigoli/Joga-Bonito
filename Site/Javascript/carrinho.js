// ============================================================================
// JOGA BONITO — carrinho e checkout (carrinho.js)
// Os valores exibidos são confirmados pela API (/api/pedidos/simular): o preço,
// o cupom e o frete oficiais são calculados no servidor, não no navegador.
// ============================================================================

(() => {
  const $ = id => document.getElementById(id);
  let cupom = "";
  let resumoServidor = null;  // resposta de /simular
  let metodo = "PIX";
  let endereco = null;
  let timerPix = null;
  let enviando = false;

  // --------------------------------------------------------------- Render
  function render() {
    const itens = JB.carrinho.itens();
    if (!itens.length) {
      $("carrinho-layout").innerHTML = `
        <div class="vazio painel" style="grid-column:1/-1">
          <div class="icone-grande">0</div>
          <p>Seu carrinho está vazio.</p>
          <p><a href="catalogo.html" class="btn btn-primario">Ir para a loja</a></p>
        </div>`;
      return;
    }

    $("itens").innerHTML = itens.map(i => `
      <article class="item-carrinho">
        <a href="Produtos.html?id=${i.id}"><img src="${JB.esc(i.img)}" alt="" data-fallback="logo"></a>
        <div class="item-info">
          <h3><a href="Produtos.html?id=${i.id}">${JB.esc(i.nome)}</a></h3>
          <p class="texto-suave">Tamanho: <strong>${JB.esc(i.tamanho)}</strong> · ${JB.brl(i.preco)} cada</p>
          <p class="erro-campo" data-erro="${i.id}-${JB.esc(i.tamanho)}"></p>
        </div>
        <div class="qtd" role="group" aria-label="Quantidade de ${JB.esc(i.nome)}">
          <button type="button" data-acao="menos" data-id="${i.id}" data-tam="${JB.esc(i.tamanho)}" aria-label="Diminuir">−</button>
          <span>${i.qtd}</span>
          <button type="button" data-acao="mais" data-id="${i.id}" data-tam="${JB.esc(i.tamanho)}" aria-label="Aumentar">+</button>
        </div>
        <p class="item-subtotal">${JB.brl(i.preco * i.qtd)}</p>
        <button type="button" class="remover" data-acao="remover" data-id="${i.id}" data-tam="${JB.esc(i.tamanho)}" aria-label="Remover ${JB.esc(i.nome)}">✕</button>
      </article>`).join("");

    atualizarValoresLocais();
    sincronizarComServidor();
  }

  /** Cálculo provisório no navegador (substituído pela resposta do servidor). */
  function atualizarValoresLocais() {
    const subtotal = JB.carrinho.subtotal();
    const desconto = resumoServidor?.desconto ?? 0;
    const frete = subtotal - desconto >= JB.LIMITE_FRETE_GRATIS ? 0 : JB.VALOR_FRETE;
    exibirValores(subtotal, desconto, frete, subtotal - desconto + frete);
  }

  function exibirValores(subtotal, desconto, frete, total) {
    $("v-subtotal").textContent = JB.brl(subtotal);
    $("linha-desconto").hidden = !desconto;
    $("v-desconto").textContent = `− ${JB.brl(desconto)}`;
    $("v-frete").textContent = frete ? JB.brl(frete) : "Grátis";
    $("v-total").textContent = JB.brl(total);
    $("checkout-total").textContent = JB.brl(total);
    $("v-parcelas").textContent = total > 0 ? `ou 6x de ${JB.brl(total / 6)} sem juros no cartão` : "";
    // Joga Junto: 1% dos produtos (com desconto, sem frete) — o valor oficial é calculado no servidor
    const jogaJunto = Math.round(subtotal - desconto) / 100;
    $("v-joga-junto").hidden = !(jogaJunto > 0);
    $("v-joga-junto").innerHTML = `<strong>${JB.brl(jogaJunto)}</strong> deste pedido vão para escolinhas de futebol (Joga Junto).`;

    const falta = JB.LIMITE_FRETE_GRATIS - (subtotal - desconto);
    $("frete-texto").innerHTML = falta > 0
      ? `Faltam <strong>${JB.brl(falta)}</strong> para o frete grátis`
      : "Você ganhou <strong>frete grátis</strong>.";
    $("frete-progresso").style.width = `${Math.min(100, ((subtotal - desconto) / JB.LIMITE_FRETE_GRATIS) * 100)}%`;
    preencherParcelas(total);
  }

  /** Confirma preços, estoque e cupom no servidor (somente logado). */
  async function sincronizarComServidor() {
    JB.aviso($("aviso-carrinho"), "");
    document.querySelectorAll("[data-erro]").forEach(e => e.textContent = "");
    if (!JB.sessao.logado()) {
      $("aviso-carrinho").hidden = false;
      JB.aviso($("aviso-carrinho"), "Entre na sua conta para aplicar cupons e finalizar a compra.", "info");
      return true;
    }
    try {
      resumoServidor = await JB.api("/api/pedidos/simular", {
        metodo: "POST", autenticado: true, corpo: { itens: JB.carrinho.paraApi(), cupom: cupom || null }
      });
      // Atualiza preços locais se mudaram no catálogo
      const itens = JB.carrinho.itens();
      let mudou = false;
      resumoServidor.itens.forEach(s => {
        const local = itens.find(i => i.id === s.produtoId && i.tamanho === s.tamanho);
        if (local && local.preco !== s.preco) { local.preco = s.preco; mudou = true; }
      });
      if (mudou) { JB.carrinho.salvar(itens); JB.toast("Alguns preços foram atualizados."); }
      exibirValores(resumoServidor.subtotal, resumoServidor.desconto, resumoServidor.frete, resumoServidor.total);
      return true;
    } catch (e) {
      resumoServidor = null;
      if (cupom && /cupom/i.test(e.message)) {
        $("cupom-msg").textContent = e.message;
        cupom = "";
        return sincronizarComServidor();
      }
      JB.aviso($("aviso-carrinho"), e.message);
      atualizarValoresLocais();
      return false;
    }
  }

  // -------------------------------------------------------------- Eventos
  $("itens")?.addEventListener("click", e => {
    const b = e.target.closest("button[data-acao]");
    if (!b) return;
    const id = Number(b.dataset.id), tam = b.dataset.tam;
    const item = JB.carrinho.itens().find(i => i.id === id && i.tamanho === tam);
    if (!item) return;
    if (b.dataset.acao === "mais") JB.carrinho.alterar(id, tam, item.qtd + 1);
    if (b.dataset.acao === "menos") JB.carrinho.alterar(id, tam, item.qtd - 1);
    if (b.dataset.acao === "remover") JB.carrinho.alterar(id, tam, 0);
    render();
  });

  $("form-cupom")?.addEventListener("submit", async e => {
    e.preventDefault();
    const codigo = $("cupom").value.trim().toUpperCase();
    if (!codigo) return;
    if (!JB.sessao.logado()) {
      try {
        const r = await JB.api("/api/cupons/validar", { metodo: "POST", corpo: { codigo, subtotal: JB.carrinho.subtotal() } });
        $("cupom-msg").textContent = r.valido ? `${r.mensagem} Entre na conta para usar.` : r.mensagem;
      } catch (err) { $("cupom-msg").textContent = err.message; }
      return;
    }
    cupom = codigo;
    $("cupom-msg").textContent = "";
    if (await sincronizarComServidor() && resumoServidor?.cupom) {
      $("cupom-msg").textContent = `Cupom ${resumoServidor.cupom} aplicado ✔`;
    }
  });

  $("btn-finalizar")?.addEventListener("click", async () => {
    if (!JB.exigirLogin()) return;
    if (!(await sincronizarComServidor())) return;
    abrirEtapa(1);
    $("checkout").showModal();
    $("cep").focus();
  });

  // ------------------------------------------------------------- Checkout
  function abrirEtapa(n) {
    [1, 2, 3].forEach(k => {
      $(`etapa-${k}`).hidden = k !== n;
      document.querySelector(`.etapas [data-etapa="${k}"]`).classList.toggle("ativa", k <= n);
    });
    if (n === 2) escolherMetodo(metodo);
  }

  $("fechar-checkout").addEventListener("click", () => {
    $("checkout").close();
    clearInterval(timerPix);
    if (!$("etapa-3").hidden) location.href = "pedidos.html";
  });

  // CEP: máscara + preenchimento automático pela API pública ViaCEP
  $("cep").addEventListener("input", async e => {
    let v = e.target.value.replace(/\D/g, "").slice(0, 8);
    e.target.value = v.length > 5 ? `${v.slice(0, 5)}-${v.slice(5)}` : v;
    $("cep-msg").textContent = "";
    if (v.length !== 8) return;
    try {
      const r = await fetch(`https://viacep.com.br/ws/${v}/json/`);
      const d = await r.json();
      if (d.erro) { $("cep-msg").textContent = "CEP não encontrado."; return; }
      $("rua").value = d.logradouro || "";
      $("bairro").value = d.bairro || "";
      $("cidade").value = d.localidade || "";
      $("uf").value = d.uf || "";
      $("numero").focus();
    } catch {
      $("cep-msg").textContent = "Não foi possível consultar o CEP; preencha manualmente.";
    }
  });

  $("etapa-1").addEventListener("submit", e => {
    e.preventDefault();
    const campos = ["cep", "rua", "numero", "bairro", "cidade", "uf"];
    let ok = true;
    campos.forEach(c => {
      const vazio = !$(c).value.trim();
      $(c).setAttribute("aria-invalid", vazio);
      if (vazio) ok = false;
    });
    if ($("cep").value.replace(/\D/g, "").length !== 8) { $("cep").setAttribute("aria-invalid", true); ok = false; }
    if (!/^[A-Za-z]{2}$/.test($("uf").value.trim())) { $("uf").setAttribute("aria-invalid", true); ok = false; }
    if (!ok) return JB.aviso($("aviso-etapa-1"), "Confira os campos destacados.");
    JB.aviso($("aviso-etapa-1"), "");
    endereco = {
      cep: $("cep").value.replace(/\D/g, ""), rua: $("rua").value.trim(), numero: $("numero").value.trim(),
      complemento: $("complemento").value.trim() || null, bairro: $("bairro").value.trim(),
      cidade: $("cidade").value.trim(), estado: $("uf").value.trim().toUpperCase()
    };
    abrirEtapa(2);
  });

  $("voltar-etapa-1").addEventListener("click", () => { clearInterval(timerPix); abrirEtapa(1); });

  document.querySelectorAll(".metodo").forEach(b => b.addEventListener("click", () => escolherMetodo(b.dataset.metodo)));

  function escolherMetodo(m) {
    metodo = m;
    document.querySelectorAll(".metodo").forEach(b => {
      const sel = b.dataset.metodo === m;
      b.classList.toggle("selecionado", sel);
      b.setAttribute("aria-checked", sel);
    });
    $("pag-pix").hidden = m !== "PIX";
    $("pag-cartao").hidden = m === "PIX";
    $("campo-parcelas").hidden = m !== "Cartão de Crédito";
    $("confirmar-pagamento").textContent = m === "PIX" ? "Já paguei — confirmar" : "Pagar agora";
    clearInterval(timerPix);
    if (m === "PIX") iniciarTimerPix();
  }

  function iniciarTimerPix() {
    let s = 15 * 60;
    $("pix-timer").textContent = "15:00";
    timerPix = setInterval(() => {
      s--;
      $("pix-timer").textContent = s <= 0 ? "expirado" : `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
      if (s <= 0) clearInterval(timerPix);
    }, 1000);
  }

  $("copiar-pix").addEventListener("click", async () => {
    try { await navigator.clipboard.writeText($("pix-codigo").value); JB.toast("Código Pix copiado!"); }
    catch { $("pix-codigo").select(); }
  });

  function preencherParcelas(total) {
    const sel = $("parcelas");
    if (!sel) return;
    const atual = sel.value || "1";
    sel.innerHTML = [1, 2, 3, 4, 5, 6]
      .filter(n => n === 1 || total / n >= 30)
      .map(n => `<option value="${n}">${n}x de ${JB.brl(total / n)} sem juros</option>`).join("");
    if ([...sel.options].some(o => o.value === atual)) sel.value = atual;
  }

  // Máscaras do cartão
  $("cartao-numero").addEventListener("input", e => {
    e.target.value = e.target.value.replace(/\D/g, "").slice(0, 16).replace(/(\d{4})(?=\d)/g, "$1 ");
  });
  $("cartao-nome").addEventListener("input", e => {
    e.target.value = e.target.value.toUpperCase().replace(/[^A-ZÀ-Ú\s]/g, "");
  });
  $("cartao-validade").addEventListener("input", e => {
    const v = e.target.value.replace(/\D/g, "").slice(0, 4);
    e.target.value = v.length > 2 ? `${v.slice(0, 2)}/${v.slice(2)}` : v;
  });
  $("cartao-cvv").addEventListener("input", e => { e.target.value = e.target.value.replace(/\D/g, "").slice(0, 4); });

  // Limpa a mensagem de erro do campo assim que o usuário corrige
  ["cartao-numero", "cartao-nome", "cartao-validade", "cartao-cvv"].forEach(c =>
    $(c).addEventListener("input", () => { $(`erro-${c}`).textContent = ""; $(c).removeAttribute("aria-invalid"); }));

  function luhn(numero) {
    let soma = 0, dobrar = false;
    for (let i = numero.length - 1; i >= 0; i--) {
      let n = Number(numero[i]);
      if (dobrar) { n *= 2; if (n > 9) n -= 9; }
      soma += n;
      dobrar = !dobrar;
    }
    return numero.length >= 13 && soma % 10 === 0;
  }

  function validarCartao() {
    const erros = {
      "cartao-numero": luhn($("cartao-numero").value.replace(/\D/g, "")) ? "" : "Número de cartão inválido.",
      "cartao-nome": $("cartao-nome").value.trim().length >= 3 ? "" : "Informe o nome impresso.",
      "cartao-validade": (() => {
        const m = $("cartao-validade").value.match(/^(\d{2})\/(\d{2})$/);
        if (!m || +m[1] < 1 || +m[1] > 12) return "Use o formato MM/AA.";
        const fim = new Date(2000 + +m[2], +m[1], 0, 23, 59);
        return fim < new Date() ? "Cartão vencido." : "";
      })(),
      "cartao-cvv": /^\d{3,4}$/.test($("cartao-cvv").value) ? "" : "CVV com 3 ou 4 dígitos."
    };
    Object.entries(erros).forEach(([campo, msg]) => {
      $(`erro-${campo}`).textContent = msg;
      $(campo).setAttribute("aria-invalid", !!msg);
    });
    return Object.values(erros).every(m => !m);
  }

  $("confirmar-pagamento").addEventListener("click", async () => {
    if (enviando) return;
    if (metodo !== "PIX" && !validarCartao()) return;

    const btn = $("confirmar-pagamento");
    enviando = true;
    btn.disabled = true;
    btn.textContent = "Processando…";
    JB.aviso($("aviso-etapa-2"), "");

    try {
      // Simula o tempo de resposta de um gateway de pagamento
      await new Promise(r => setTimeout(r, 900));
      const parcelas = metodo === "Cartão de Crédito" ? Number($("parcelas").value) : 1;
      const pedido = await JB.api("/api/pedidos", {
        metodo: "POST", autenticado: true,
        corpo: { itens: JB.carrinho.paraApi(), formaPagamento: metodo, parcelas, cupom: cupom || null, endereco, origem: "Web" }
      });
      clearInterval(timerPix);
      JB.carrinho.limpar();
      $("sucesso-numero").textContent = `#${pedido.pedidoId}`;
      $("sucesso-pagamento").textContent = `${metodo}${parcelas > 1 ? ` em ${parcelas}x` : ""} · ${JB.brl(pedido.total)}`;
      $("sucesso-rastreio").textContent = pedido.codigoRastreio;
      $("sucesso-joga-junto").textContent = pedido.jogaJunto > 0
        ? `${JB.brl(pedido.jogaJunto)} deste pedido foram registrados para o programa Joga Junto.` : "";
      abrirEtapa(3);
    } catch (e) {
      JB.aviso($("aviso-etapa-2"), e.message);
    } finally {
      enviando = false;
      btn.disabled = false;
      btn.textContent = metodo === "PIX" ? "Já paguei — confirmar" : "Pagar agora";
    }
  });

  render();
})();
