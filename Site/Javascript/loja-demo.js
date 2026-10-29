// ============================================================================
// JOGA BONITO — motor da loja de demonstração (loja-demo.js)
//
// O MESMO contrato da API .NET (rotas, códigos HTTP, JSON, regras de estoque, cupom,
// frete, Joga Junto, pedidos, moderação, LGPD, sessão e CSRF), em JavaScript puro.
// Usado em dois lugares, para nunca divergir:
//   * testes E2E: tests/e2e/mock-api.js serve a loja com este motor (Node);
//   * site público (GitHub Pages / Vercel): com JB_CONFIG.modo = "demo", as chamadas a
//     /api e /health são respondidas aqui mesmo, no navegador do visitante, e os dados
//     ficam só no navegador dele (localStorage). Não há servidor nem banco envolvidos.
// ============================================================================
(function (raiz) {
  "use strict";

  function criarLoja(produtosIniciais, opcoes = {}) {
    const salvo = (opcoes.carregar && opcoes.carregar()) || {};
    const produtos = salvo.produtos || JSON.parse(JSON.stringify(produtosIniciais));
    const usuariosPadrao = [
      { id: 1, nome: "Administrador Joga Bonito", email: "admin@jogabonito.com", senha: "Admin@2026", role: "Admin" },
      { id: 2, nome: "Matheus Sigoli", email: "matheus@estudante.com", senha: "Cliente@2026", role: "Cliente" },
      { id: 3, nome: "Professor Avaliador", email: "professor@unip.br", senha: "Unip@2026", role: "Cliente" }
    ].map(u => ({ ...u, falhas: 0, bloqueadoAte: 0, versao: 1 }));
    const MAX_TENTATIVAS = 5, MINUTOS_BLOQUEIO = 15;

    const cupons = { BEMVINDO10: { p: 10, min: 0 }, RETRO15: { p: 15, min: 500 }, HEXA2026: { p: 5, min: 0 } };
    const pedidos = salvo.pedidos || [];
    const acessos = salvo.acessos || [];
    const auditoria = salvo.auditoria || [];
    const avaliacoesPadrao = [{ id: 1, produtoId: 1, usuarioId: 2, cliente: "Matheus", nota: 5, comentario: "Tecido muito bom.",
      status: "Publicada", data: new Date().toISOString() }];
    // Mesma regra de ModeracaoAvaliacao.cs: link/contato vai para moderação
    const precisaModerar = t => /(https?:\/\/|www\.|\b[\w.-]+\.(com|net|org|br)\b|[\w.+-]+@[\w-]+\.\w+|(\d[\s.-]?){8,})/i.test(t || "");
    const jogaJunto = valor => (valor <= 0 ? 0 : Math.round(valor) / 100);



    const resumo = p => {
      const { imgs, tamanhos, ...r } = p;
      const av = avaliacoes.filter(a => a.produtoId === p.id && a.status === "Publicada");
      r.estoque = tamanhos.reduce((s, t) => s + t.quantidade, 0);
      r.totalAvaliacoes = av.length;
      r.notaMedia = av.length ? av.reduce((s, a) => s + a.nota, 0) / av.length : 0;
      return r;
    };
    const frete = v => (v <= 0 || v >= 299 ? 0 : 19.9);
    // Mesmas regras de StatusPedidoRegras (Pedido.cs) e sp_AtualizarStatusPedido
    const ORDEM_STATUS = ["Aguardando Pagamento", "Pago", "Em Separação", "Enviado", "Entregue"];
    const podeMudar = (atual, novo) => {
      if (atual === "Entregue" || atual === "Cancelado") return false;
      if (novo === "Cancelado") return atual !== "Enviado";
      return ORDEM_STATUS.indexOf(novo) > ORDEM_STATUS.indexOf(atual);
    };
    const devolverEstoque = x => x.itens.forEach(i => {
      const t = produtos.find(p => p.id === i.produtoId).tamanhos.find(t => t.tamanho === i.tamanho);
      auditoria.unshift({ id: auditoria.length + 1, produtoId: i.produtoId, produto: i.nome, tamanho: i.tamanho,
        qtdAnterior: t.quantidade, qtdNova: t.quantidade + i.qtd, origem: `Cancelamento - Pedido #${x.id}`, data: new Date().toISOString() });
      t.quantidade += i.qtd;
    });
    const mudarStatus = (x, novo) => {
      if (!podeMudar(x.status, novo)) throw [400, `Não é possível mudar de '${x.status}' para '${novo}'.`];
      if (novo === "Cancelado") devolverEstoque(x);
      x.status = novo;
      x.historico.push({ status: novo, data: new Date().toISOString() });
    };
    const enderecos = salvo.enderecos || [];
    const imagemValida = c => /^\.\.\/IMG\/[A-Za-z0-9 _\/-]{1,180}\.(jpg|jpeg|png|webp|svg)$/i.test(c || "") && !String(c).includes("//");
    // Token simulado "tok-<id>-v<versao>": a versão precisa bater com a da conta (como o claim "ver" da API real)
    const tokenDe = u => `tok-${u.id}-v${u.versao}`;
    const sessaoDe = u => ({ token: tokenDe(u), expiraEm: new Date(Date.now() + 8 * 3600e3).toISOString(),
      usuario: { id: u.id, nome: u.nome, email: u.email, role: u.role } });
    // Sessão do site: cookie HttpOnly "jb_sessao" (como CookieSessao.cs). App: Authorization: Bearer.
    const cookieDe = req => {
      const m = (req.headers.cookie || "").match(/(?:^|;\s*)jb_sessao=([^;]+)/);
      return m ? decodeURIComponent(m[1]) : "";
    };
    const usuarioDoToken = req => {
      const t = (req.headers.authorization || "").replace("Bearer ", "") || cookieDe(req);
      if (!t) return undefined;
      const u = usuarios.find(x => t.startsWith(`tok-${x.id}-`));
      return u && tokenDe(u) === t ? u : null;          // null = token recusado (sessão encerrada)
    };
    const hhmm = ms => new Date(ms).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
    // Mesma política de Usuario.ValidarForcaSenha: 8 a 72 bytes, letras e números, fora da lista comum, sem o e-mail
    const COMUNS = ["senha123", "senha1234", "senha2026", "12345678a", "abc12345", "abcd1234", "qwerty123", "password1",
      "brasil123", "brasil2026", "flamengo123", "admin123", "mudar123", "jogabonito2026", "futebol123", "teste123"];
    function validarSenha(s, email) {
      if (typeof s !== "string" || s.length < 8 || new TextEncoder().encode(s).length > 72 || !/\p{L}/u.test(s) || !/\d/.test(s))
        throw [400, "A senha deve ter de 8 a 72 caracteres, com letras e números."];
      if (COMUNS.includes(s.toLowerCase()) || new Set(s).size <= 3)
        throw [400, "Essa senha é muito comum. Escolha outra, de preferência uma frase."];
      const local = String(email || "").trim().toLowerCase().split("@")[0];
      if (local.length >= 4 && s.toLowerCase().includes(local)) throw [400, "A senha não pode conter o seu e-mail."];
    }
    // Mesmas máscaras de Mascara.cs
    const mascaraEmail = e => { const i = (e || "").indexOf("@"); if (i <= 0) return "***";
      const n = e.slice(0, i), v = n.length <= 2 ? n.slice(0, 1) : n.slice(0, 2);
      return v + "*".repeat(Math.max(3, n.length - v.length)) + e.slice(i); };
    const mascaraIp = ip => { if (!ip) return ip; const v4 = String(ip).replace(/^::ffff:/, "");
      if (/^\d+\.\d+\.\d+\.\d+$/.test(v4)) return v4.split(".").slice(0, 3).join(".") + ".x";
      const p = String(ip).split(":").filter(Boolean); return p.length >= 3 ? `${p[0]}:${p[1]}:${p[2]}::x` : "::x"; };

    function registrarAcesso(email, sucesso, ip, detalhe) {
      acessos.unshift({ id: acessos.length + 1, email, ip, sucesso, detalhe, data: new Date().toISOString() });
    }

    function simular(itens, cupom) {
      if (!itens?.length) throw [400, "Seu carrinho está vazio."];
      const linhas = itens.map(i => {
        const p = produtos.find(x => x.id === i.produtoId);
        if (!p) throw [400, `Produto ${i.produtoId} não está disponível.`];
        const t = p.tamanhos.find(x => x.tamanho === i.tamanho);
        if (!t) throw [400, `Tamanho '${i.tamanho}' inválido para ${p.nome}.`];
        if (t.quantidade < i.quantidade)
          throw [400, t.quantidade ? `Restam apenas ${t.quantidade} unidade(s) de ${p.nome} (${i.tamanho}).` : `${p.nome} (${i.tamanho}) está esgotado.`];
        return { produtoId: p.id, nome: p.nome, img: p.img, tamanho: i.tamanho, qtd: i.quantidade, preco: p.precoFinal, subtotal: p.precoFinal * i.quantidade };
      });
      const subtotal = +linhas.reduce((s, l) => s + l.subtotal, 0).toFixed(2);
      let desconto = 0;
      if (cupom) {
        const c = cupons[cupom.toUpperCase()];
        if (!c) throw [400, "Cupom inválido ou expirado."];
        if (subtotal < c.min) throw [400, "Este cupom vale para compras a partir de R$ 500,00."];
        desconto = +(subtotal * c.p / 100).toFixed(2);
      }
      const f = frete(subtotal - desconto);
      return { itens: linhas, subtotal, desconto, frete: f, total: +(subtotal - desconto + f).toFixed(2), cupom: cupom ? cupom.toUpperCase() : null,
        jogaJunto: jogaJunto(subtotal - desconto) };
    }

    function rotear(req, url, b, u, ctx) {
      const ehSite = String(req.headers["x-jb-cliente"] || "").toLowerCase() === "web";
      const entregar = sessao => {
        if (!ehSite) return sessao;
        ctx.cookies.push(`jb_sessao=${encodeURIComponent(sessao.token)}; HttpOnly; SameSite=Strict; Path=/; Max-Age=28800`);
        return { ...sessao, token: "" };
      };
      const apagarCookie = () => ctx.cookies.push("jb_sessao=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0");
      const p = url.pathname, m = req.method, q = url.searchParams;
      const ip = req.socket.remoteAddress;
      const precisa = papel => {
        if (u === null) { apagarCookie(); throw [401, "Sessão encerrada. Entre novamente."]; }
        if (!u) throw [401, "Faça login para continuar."];
        if (papel && u.role !== papel) throw [403, "Acesso restrito ao administrador."];
      };
      let r;

      if (p === "/health" || p === "/health/live") return [200, "Healthy"];
      if (p === "/health/ready") return [200, { status: "Healthy", componentes: [
        { nome: "sqlserver", status: "Healthy", descricao: "SQL Server acessível. (simulado)", duracaoMs: 3.2 }], duracaoMs: 3.4 }];

      // ------------------------------ Autenticação ------------------------------
      if (p === "/api/auth/login" && m === "POST") {
        const email = String(b.email || "").trim().toLowerCase();
        const x = usuarios.find(v => v.email === email);
        if (!x) { registrarAcesso(email, false, ip, "E-mail não cadastrado"); throw [401, "E-mail ou senha incorretos."]; }
        if (x.bloqueadoAte > Date.now()) {
          registrarAcesso(email, false, ip, "Conta bloqueada");
          throw [423, `Conta bloqueada por segurança após várias senhas incorretas. Tente novamente após as ${hhmm(x.bloqueadoAte)}.`];
        }
        if (x.senha !== b.senha) {
          registrarAcesso(email, false, ip, "Senha incorreta");
          if (++x.falhas >= MAX_TENTATIVAS) {
            x.falhas = 0;
            x.bloqueadoAte = Date.now() + MINUTOS_BLOQUEIO * 60e3;
            throw [423, `Conta bloqueada por segurança após várias senhas incorretas. Tente novamente após as ${hhmm(x.bloqueadoAte)}.`];
          }
          throw [401, "E-mail ou senha incorretos."];
        }
        x.falhas = 0;
        registrarAcesso(email, true, ip, "Login");
        return [200, entregar(sessaoDe(x))];
      }
      if (p === "/api/auth/cadastro" && m === "POST") {
        if (!b.aceiteLgpd) throw [400, "É preciso aceitar a Política de Privacidade para criar a conta."];
        validarSenha(b.senha, b.email);
        const email = String(b.email || "").trim().toLowerCase();
        if (usuarios.some(v => v.email === email)) throw [400, "Este e-mail já está cadastrado."];
        const n = { id: usuarios.length + 1, nome: b.nome, email, senha: b.senha, role: "Cliente", falhas: 0, bloqueadoAte: 0, versao: 1 };
        usuarios.push(n);
        return [201, { id: n.id, nome: n.nome, email: n.email, role: "Cliente" }];
      }
      if (p === "/api/auth/me") { precisa(); return [200, { id: u.id, nome: u.nome, email: u.email, role: u.role }]; }
      if (p === "/api/auth/trocar-senha" && m === "POST") {
        precisa();
        if (b.senhaAtual !== u.senha) throw [400, "A senha atual não confere."];
        validarSenha(b.novaSenha, u.email);
        if (b.novaSenha === b.senhaAtual) throw [400, "A nova senha deve ser diferente da atual."];
        u.senha = b.novaSenha;
        u.versao++;                                       // derruba as outras sessões
        return [200, entregar(sessaoDe(u))];              // e devolve um token novo para esta
      }
      if (p === "/api/auth/sair-de-todos" && m === "POST") { precisa(); u.versao++; apagarCookie(); return [204]; }
      if (p === "/api/auth/sair" && m === "POST") { apagarCookie(); return [204]; }
      if (p === "/api/auth/meus-dados") {
        precisa();
        return [200, { conta: { id: u.id, nome: u.nome, email: u.email, telefone: null, perfil: u.role, criadoEm: new Date().toISOString(), aceiteLgpdEm: new Date().toISOString() },
          enderecos: enderecos.filter(e => e.usuarioId === u.id).map(({ usuarioId, ...e }) => e), pedidos: pedidos.filter(x => x.usuarioId === u.id),
          avaliacoes: avaliacoes.filter(a => a.usuarioId === u.id).map(a => ({ produto: produtos.find(x => x.id === a.produtoId).nome, nota: a.nota, comentario: a.comentario, status: a.status, data: a.data })),
          acessos: acessos.filter(a => a.email === u.email), geradoEm: new Date().toISOString(),
          observacao: "Dados pessoais mantidos pela Joga Bonito (LGPD, art. 18, II e V)." }];
      }
      if (p === "/api/auth/excluir-conta" && m === "POST") {
        precisa();
        if (b.senha !== u.senha) throw [400, "Senha incorreta. Para excluir a conta, confirme sua senha atual."];
        if (u.role === "Admin") throw [400, "Contas de administrador não podem ser excluídas por aqui."];
        const antigo = u.email;
        Object.assign(u, { nome: "Cliente removido", email: `removido-${u.id}@anonimo.invalid`, senha: "!removido" });
        u.versao++;
        for (let i = avaliacoes.length - 1; i >= 0; i--) if (avaliacoes[i].usuarioId === u.id) avaliacoes.splice(i, 1);
        acessos.forEach(a => { if (a.email === antigo) { a.email = u.email; a.ip = null; } });
        apagarCookie();
        return [204];
      }

      // -------------------------------- Catálogo --------------------------------
      if (p === "/api/categorias") return [200, [
        { id: 1, nome: "Temporada 2026", slug: "temporada-2026", descricao: "" },
        { id: 2, nome: "Camisas Retrô", slug: "retro", descricao: "" },
        { id: 3, nome: "Chuteiras", slug: "chuteiras", descricao: "" }]];
      if (p === "/api/produtos") {
        const busca = (q.get("busca") || "").toLowerCase();
        const l = produtos.filter(x => x.ativo !== false).map(resumo)
          .filter(x => !q.get("categoria") || x.categoriaSlug === q.get("categoria"))
          .filter(x => !q.get("linha") || x.linha === q.get("linha"))
          .filter(x => !q.get("marca") || (x.marca || "").toLowerCase() === q.get("marca").toLowerCase())
          .filter(x => !q.get("precoMax") || x.precoFinal <= Number(q.get("precoMax")))
          .filter(x => !q.get("destaque") || x.destaque)
          .filter(x => !busca || [x.nome, x.equipe, x.modelo, x.marca, x.solado, String(x.ano)]
            .some(c => (c || "").toLowerCase().includes(busca)));
        const ordens = { "menor-preco": (a, c) => a.precoFinal - c.precoFinal, "maior-preco": (a, c) => c.precoFinal - a.precoFinal,
          "nome": (a, c) => a.nome.localeCompare(c.nome), "novidades": (a, c) => c.id - a.id };
        l.sort(ordens[q.get("ordem")] || ((a, c) => (c.destaque - a.destaque) || (a.id - c.id)));
        return [200, l];
      }
      if ((r = p.match(/^\/api\/produtos\/(\d+)$/))) {
        const x = produtos.find(v => v.id === +r[1] && v.ativo !== false);
        if (!x) throw [404, "Produto não encontrado."];
        return [200, { produto: resumo(x), tipo: x.categoriaSlug === "chuteiras" ? "Chuteira" : "Camisa", imgs: x.imgs, tamanhos: x.tamanhos }];
      }
      if ((r = p.match(/^\/api\/produtos\/(\d+)\/avaliacoes$/))) {
        const produtoId = +r[1];
        if (m === "POST") {
          precisa();
          const comprou = pedidos.some(x => x.usuarioId === u.id && x.status !== "Cancelado" && x.itens.some(i => i.produtoId === produtoId));
          if (!comprou) throw [400, "Somente clientes que compraram este produto podem avaliá-lo."];
          const status = precisaModerar(b.comentario) ? "Pendente" : "Publicada";
          const existente = avaliacoes.find(a => a.produtoId === produtoId && a.usuarioId === u.id);
          const dados = { nota: b.nota, comentario: b.comentario, data: new Date().toISOString(),
            status: existente && existente.status === "Oculta" ? "Pendente" : status };
          if (existente) Object.assign(existente, dados);
          else avaliacoes.push({ id: avaliacoes.length + 1, produtoId, usuarioId: u.id, cliente: u.nome.split(" ")[0], ...dados });
          return [200, dados.status === "Publicada"
            ? { status: "Publicada", mensagem: "Obrigado pela avaliação!" }
            : { status: dados.status, mensagem: "Recebemos sua avaliação. Ela aparece na loja depois de revisada pela equipe." }];
        }
        return [200, avaliacoes.filter(a => a.produtoId === produtoId && a.status === "Publicada")];
      }
      if (p === "/api/cupons/validar") {
        const c = cupons[(b.codigo || "").toUpperCase()];
        return [200, c
          ? { valido: true, codigo: b.codigo, percentual: c.p, desconto: 0, mensagem: `Cupom aplicado: ${c.p}% de desconto.` }
          : { valido: false, codigo: b.codigo, percentual: 0, desconto: 0, mensagem: "Cupom inválido ou expirado." }];
      }

      // -------------------------------- Pedidos ---------------------------------
      if (p === "/api/pedidos/simular") { precisa(); return [200, simular(b.itens, b.cupom)]; }
      if (p === "/api/pedidos" && m === "POST") {
        precisa();
        const s = simular(b.itens, b.cupom);
        const id = pedidos.length + 1, agora = new Date().toISOString();
        if (b.endereco) enderecos.push({ usuarioId: u.id, ...b.endereco });
        b.itens.forEach(i => {
          const prod = produtos.find(x => x.id === i.produtoId);
          const t = prod.tamanhos.find(t => t.tamanho === i.tamanho);
          auditoria.unshift({ id: auditoria.length + 1, produtoId: prod.id, produto: prod.nome, tamanho: i.tamanho,
            qtdAnterior: t.quantidade, qtdNova: t.quantidade - i.quantidade, origem: `Venda - Pedido #${id}`, data: agora });
          t.quantidade -= i.quantidade;
        });
        pedidos.unshift({ id, usuarioId: u.id, data: agora, status: "Pago", formaPagamento: b.formaPagamento, parcelas: b.parcelas,
          codigoRastreio: `JB${String(id).padStart(9, "0")}BR`, origem: b.origem || "Web", subtotal: s.subtotal, desconto: s.desconto,
          frete: s.frete, total: s.total, cliente: u.nome, itens: s.itens, historico: [{ status: "Pago", data: agora }] });
        pedidos[0].jogaJunto = s.jogaJunto;
        return [201, { pedidoId: id, codigoRastreio: pedidos[0].codigoRastreio, subtotal: s.subtotal, desconto: s.desconto, frete: s.frete,
          total: s.total, status: "Pago", jogaJunto: s.jogaJunto }];
      }
      if (p === "/api/pedidos/meus") { precisa(); return [200, pedidos.filter(x => x.usuarioId === u.id)]; }
      if ((r = p.match(/^\/api\/pedidos\/(\d+)\/cancelar$/))) {
        precisa();
        const x = pedidos.find(v => v.id === +r[1] && v.usuarioId === u.id);
        if (!x) throw [404, "Pedido não encontrado."];
        if (!["Aguardando Pagamento", "Pago"].includes(x.status))
          throw [400, "Este pedido já está em separação e não pode ser cancelado pelo site. Fale com o atendimento."];
        mudarStatus(x, "Cancelado");
        return [204];
      }
      if ((r = p.match(/^\/api\/pedidos\/(\d+)$/)) && m === "GET") {
        precisa();
        const x = pedidos.find(v => v.id === +r[1]);
        if (!x || (x.usuarioId !== u.id && u.role !== "Admin")) throw [404, "Pedido não encontrado."];  // 404: não confirma que existe
        return [200, x];
      }

      // ---------------------------------- Admin ---------------------------------
      if (p.startsWith("/api/admin")) {
        precisa("Admin");
        if (p === "/api/admin/dashboard") return [200, {
          totalProdutos: produtos.length, totalPecasEstoque: produtos.reduce((s, x) => s + resumo(x).estoque, 0), totalClientes: 2,
          totalPedidos: pedidos.length, faturamentoTotal: pedidos.reduce((s, x) => s + x.total, 0), faturamento30Dias: 1234.5,
          ticketMedio30Dias: 411.5, tamanhosEsgotados: 9, tamanhosEstoqueBaixo: 12, pedidosPendentesEnvio: 2,
          vendasPorCategoria: [{ categoria: "Temporada 2026", unidades: 3, receita: 1049.7 }, { categoria: "Chuteiras", unidades: 1, receita: 549.9 }],
          maisVendidos: [{ produtoId: 1, nome: "Camisa Brasil 2026 Home", categoria: "Temporada 2026", unidades: 2, receita: 699.8 }],
          totalJogaJunto: +pedidos.filter(x => x.status !== "Cancelado").reduce((s, x) => s + (x.jogaJunto || 0), 0).toFixed(2),
          avaliacoesPendentes: avaliacoes.filter(a => a.status === "Pendente").length }];
        if (p === "/api/admin/avaliacoes") {
          const st = q.get("status");
          return [200, avaliacoes.filter(a => !st || a.status === st).map(a => ({
            id: a.id, produtoId: a.produtoId, produto: produtos.find(x => x.id === a.produtoId).nome, cliente: a.cliente,
            nota: a.nota, comentario: a.comentario, status: a.status, data: a.data, motivoModeracao: a.motivo || null,
            moderador: a.moderador || null, moderadoEm: a.moderadoEm || null }))];
        }
        if ((r = p.match(/^\/api\/admin\/avaliacoes\/(\d+)$/)) && m === "PUT") {
          const a = avaliacoes.find(x => x.id === +r[1]);
          if (!a) throw [404, "Avaliação não encontrada."];
          if (!["Publicada", "Oculta"].includes(b.status)) throw [400, "Use Publicada ou Oculta."];
          if (b.status === "Oculta" && !(b.motivo || "").trim()) throw [400, "Informe o motivo para ocultar a avaliação."];
          Object.assign(a, { status: b.status, motivo: b.motivo || null, moderador: u.email, moderadoEm: new Date().toISOString() });
          return [204];
        }
        if (p === "/api/admin/pedidos") return [200, pedidos];
        if ((r = p.match(/^\/api\/admin\/pedidos\/(\d+)\/status$/))) {
          const x = pedidos.find(v => v.id === +r[1]);
          if (!x) throw [404, "Pedido não encontrado."];
          mudarStatus(x, b.status);
          return [204];
        }
        if (p === "/api/admin/estoque" && m === "GET") return [200, produtos.flatMap(x => x.tamanhos.map(t => ({
          produtoId: x.id, nome: x.nome, linha: x.linha, categoria: x.categoria, tamanho: t.tamanho, quantidade: t.quantidade,
          statusNivel: t.quantidade === 0 ? "ESGOTADO" : t.quantidade < 5 ? "BAIXO" : "REGULAR", ultimaAtualizacao: new Date().toISOString() })))];
        if (p === "/api/admin/estoque" && m === "PUT") {
          if (!(b.quantidade >= 0 && b.quantidade <= 9999)) throw [400, "Quantidade deve estar entre 0 e 9999."];
          const prod = produtos.find(x => x.id === b.produtoId);
          const t = prod.tamanhos.find(t => t.tamanho === b.tamanho);
          auditoria.unshift({ id: auditoria.length + 1, produtoId: prod.id, produto: prod.nome, tamanho: b.tamanho,
            qtdAnterior: t.quantidade, qtdNova: b.quantidade, origem: "Painel Admin", data: new Date().toISOString() });
          t.quantidade = b.quantidade;
          return [204];
        }
        if (p === "/api/admin/estoque/auditoria") return [200, auditoria];
        if (p === "/api/admin/acessos") return [200, acessos.slice(0, Number(q.get("limite") || 50))
          .map(a => ({ ...a, email: mascaraEmail(a.email), ip: mascaraIp(a.ip) }))];
        if (p === "/api/admin/consultas") return [200, [{ nome: "tabelas", descricao: "Quantidade de registros em cada tabela" },
          { nome: "acessos", descricao: "Tabela LogAcessos" }]];
        if (p.startsWith("/api/admin/consultas/")) return [200, { nome: "tabelas", descricao: "Quantidade de registros em cada tabela",
          colunas: ["Tabela", "Registros"], linhas: [{ Tabela: "Produtos", Registros: produtos.length }, { Tabela: "LogAcessos", Registros: acessos.length }] }];
        if (p.startsWith("/api/admin/produtos")) {
          const id = +(p.split("/")[4] || 0);
          if (m === "DELETE") {
            const x = produtos.find(v => v.id === id);
            if (!x) throw [404, "Produto não encontrado."];
            x.ativo = false;
            return [204];
          }
          // Mesma validação de CatalogoServico.ValidarImagem
          if (![b.imagem, ...(b.imagens || [])].filter(Boolean).every(imagemValida))
            throw [400, "Imagem inválida: use um arquivo da pasta IMG, por exemplo ../IMG/Produtos/37/1.jpg."];
          if (!(b.preco > 0)) throw [400, "Preço inválido."];
          const cat = { 1: ["Temporada 2026", "temporada-2026"], 2: ["Camisas Retrô", "retro"], 3: ["Chuteiras", "chuteiras"] }[b.categoriaId];
          if (!cat) throw [400, "Categoria inválida."];
          const chut = cat[1] === "chuteiras";
          const dados = { nome: b.nome, modelo: b.modelo, linha: b.linha, equipe: b.equipe || null, ano: b.ano || null,
            marca: chut ? b.marca || null : null, solado: chut ? b.solado || null : null, descricao: b.descricao,
            preco: b.preco, precoPromocional: b.precoPromocional || null, precoFinal: b.precoPromocional || b.preco,
            img: b.imagem || "../IMG/LOGO 2.png", destaque: !!b.destaque, categoriaId: b.categoriaId, categoria: cat[0], categoriaSlug: cat[1] };
          if (m === "POST") {
            const novo = { id: Math.max(...produtos.map(x => x.id)) + 1, ...dados, imgs: [dados.img], notaMedia: 0, totalAvaliacoes: 0,
              tamanhos: (chut ? ["37", "38", "39", "40", "41", "42", "43", "44"] : ["P", "M", "G", "GG", "XG"]).map(t => ({ tamanho: t, quantidade: 0 })) };
            produtos.push(novo);
            return [201, { id: novo.id }];
          }
          const x = produtos.find(v => v.id === id);
          if (!x) throw [404, "Produto não encontrado."];
          Object.assign(x, dados);
          return [204];
        }
      }
      throw [404, "Rota inexistente na API simulada: " + p];
    }


    const usuarios = salvo.usuarios || usuariosPadrao;
    const avaliacoes = salvo.avaliacoes || avaliacoesPadrao;

    function persistir() {
      if (opcoes.salvar) opcoes.salvar({ produtos, usuarios, pedidos, acessos, auditoria, avaliacoes, enderecos });
    }

    /**
     * Atende uma requisição. cabecalhos em minúsculas (como no Node); devolve { status, dados, cookies }.
     * Mesma proteção da API: origem de outro site e escrita por cookie sem X-JB-Requisicao são recusadas.
     */
    function pedir({ metodo = "GET", url, corpo = {}, cabecalhos = {}, ip = "127.0.0.1", host = "" }) {
      const req = { method: metodo, headers: cabecalhos, socket: { remoteAddress: ip } };
      const ctx = { cookies: [] };
      try {
        if (!["GET", "HEAD", "OPTIONS"].includes(metodo) && url.pathname.startsWith("/api/")) {
          const origem = cabecalhos.origin;
          const propria = origem && host && origem === `http://${host}`;
          if (origem && !propria && !/^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origem))
            throw [403, "Origem da requisição não permitida."];
          if (cookieDe(req) && !cabecalhos.authorization && cabecalhos["x-jb-requisicao"] !== "1")
            throw [403, "Requisição recusada (proteção CSRF). Recarregue a página e tente de novo."];
        }
        const [status, dados] = rotear(req, url, corpo || {}, usuarioDoToken(req), ctx);
        if (metodo !== "GET") persistir();
        return { status, dados, cookies: ctx.cookies };
      } catch (e) {
        if (Array.isArray(e)) {
          if (metodo !== "GET") persistir();
          return { status: e[0], dados: e[1] ? { mensagem: e[1] } : undefined, cookies: ctx.cookies };
        }
        throw e;
      }
    }

    return { pedir };
  }

  // ------------------------------------------------------------------ navegador
  // Site público sem servidor: troca o fetch para /api e /health pelo motor acima.
  function instalarNoNavegador() {
    const CHAVE_LOJA = "jb_demo_loja_v1";
    const CHAVE_SESSAO = "jb_demo_sessao";
    const ler = k => { try { return localStorage.getItem(k); } catch { return null; } };
    const gravar = (k, v) => { try { v === null ? localStorage.removeItem(k) : localStorage.setItem(k, v); } catch { /* modo privado */ } };
    let loja = null;
    const obterLoja = () => loja || (loja = criarLoja(
      raiz.JB_DEMO_PRODUTOS || (typeof JB_CATALOGO_LOCAL !== "undefined" ? JB_CATALOGO_LOCAL : []), {
        carregar: () => { try { return JSON.parse(ler(CHAVE_LOJA)); } catch { return null; } },
        salvar: d => gravar(CHAVE_LOJA, JSON.stringify(d))
      }));

    const fetchOriginal = raiz.fetch.bind(raiz);
    raiz.fetch = async function (entrada, init = {}) {
      const url = new URL(typeof entrada === "string" ? entrada : entrada.url, raiz.location.href);
      if (url.origin !== raiz.location.origin || !/^\/(api|health)(\/|$)/.test(url.pathname)) return fetchOriginal(entrada, init);
      await new Promise(r => setTimeout(r, 80));                         // como uma rede rápida
      const cabecalhos = {};
      new Headers(init.headers || {}).forEach((v, k) => { cabecalhos[k] = v; });
      const sessao = ler(CHAVE_SESSAO);
      if (sessao) cabecalhos.cookie = `jb_sessao=${encodeURIComponent(sessao)}`;
      let corpo = {};
      if (typeof init.body === "string") { try { corpo = JSON.parse(init.body); } catch { /* corpo inválido */ } }
      const r = obterLoja().pedir({ metodo: (init.method || "GET").toUpperCase(), url, corpo, cabecalhos, ip: "200.150.10.27" });
      for (const c of r.cookies) {
        const m = /^jb_sessao=([^;]*)/.exec(c);
        if (m) gravar(CHAVE_SESSAO, m[1] && !/Max-Age=0/i.test(c) ? decodeURIComponent(m[1]) : null);
      }
      const texto = typeof r.dados === "string";
      return new Response(r.status === 204 || r.dados === undefined ? null : texto ? r.dados : JSON.stringify(r.dados), {
        status: r.status, headers: { "Content-Type": texto ? "text/plain" : "application/json" }
      });
    };
  }

  if (typeof module !== "undefined" && module.exports) module.exports = { criarLoja };
  else {
    raiz.JBLojaDemo = { criarLoja };
    if (raiz.JB_CONFIG && raiz.JB_CONFIG.modo === "demo") instalarNoNavegador();
  }
})(typeof window !== "undefined" ? window : globalThis);
