// ============================================================================
// JOGA BONITO — login e cadastro (auth.js)
// ============================================================================

(() => {
  const $ = id => document.getElementById(id);
  const volta = JB.parametro("volta");
  // Só aceita retorno para páginas internas (evita redirecionamento aberto)
  const destino = volta && /^[\w-]+\.html(\?[\w=&%.-]*)?$/.test(volta) ? volta : "inicial.html";

  // Mantém o "volta" ao alternar entre login e cadastro
  if (volta) {
    $("link-cadastro")?.setAttribute("href", `cadastro.html?volta=${encodeURIComponent(volta)}`);
    $("link-login")?.setAttribute("href", `login.html?volta=${encodeURIComponent(volta)}`);
  }

  document.querySelectorAll(".ver-senha").forEach(b => b.addEventListener("click", () => {
    const campo = $(b.dataset.alvo);
    const mostrar = campo.type === "password";
    campo.type = mostrar ? "text" : "password";
    b.setAttribute("aria-label", mostrar ? "Ocultar senha" : "Mostrar senha");
  }));

  const avisoEspera = m => JB.aviso($("aviso"), m, "info");

  /** Login que espera a API ligar (se preciso) em vez de falhar. */
  async function entrar(email, senha) {
    const resposta = await JB.conexao.quandoNoAr(
      () => JB.api("/api/auth/login", { metodo: "POST", corpo: { email, senha } }), avisoEspera);
    JB.sessao.salvar(resposta);
    return resposta;
  }

  /** Mensagem de erro útil: falha do servidor (5xx) vira o motivo real (ex.: banco desligado). */
  async function mensagemDe(err) {
    if (err.status >= 500) return (await JB.conexao.explicarFalha()) || err.message;
    return err.message;
  }

  // Contas de demonstração: só na loja rodando no próprio computador (em produção elas não existem)
  const caixaDemo = $("contas-demo");
  const modoDemo = window.JB_CONFIG && window.JB_CONFIG.modo === "demo";
  if (caixaDemo && (modoDemo || ["localhost", "127.0.0.1"].includes(location.hostname))) {
    caixaDemo.hidden = false;
    caixaDemo.addEventListener("click", e => {
      const b = e.target.closest("[data-email]");
      if (!b) return;
      $("email").value = b.dataset.email;
      $("senha").value = b.dataset.senha;
      $("form-login").requestSubmit();
    });
  }

  // ------------------------------------------------------------------ Login
  // Erro de formulário para quem usa leitor de tela: o aviso (role=alert) é lido, o campo fica
  // marcado como inválido e ligado ao aviso, e o foco vai para ele (WCAG 3.3.1). Achado ao conferir
  // a árvore de acessibilidade em 13/11: o aviso era lido, mas o foco ficava no botão.
  function erroNoCampo(form, campo, mensagem) {
    form.querySelectorAll("[aria-invalid]").forEach(c => c.removeAttribute("aria-invalid"));
    JB.aviso($("aviso"), mensagem);
    if (!campo) return;
    campo.setAttribute("aria-invalid", "true");
    const ligados = new Set((campo.getAttribute("aria-describedby") || "").split(" ").filter(Boolean));
    ligados.add("aviso");
    campo.setAttribute("aria-describedby", [...ligados].join(" "));
    campo.focus();
  }
  document.querySelectorAll("#form-login, #form-cadastro").forEach(f =>
    f.addEventListener("input", e => e.target.removeAttribute?.("aria-invalid")));

  const formLogin = $("form-login");
  if (formLogin) {
    if (JB.sessao.logado()) location.href = destino;
    formLogin.addEventListener("submit", async e => {
      e.preventDefault();
      const email = $("email").value.trim();
      const senha = $("senha").value;
      if (!email || !senha) return erroNoCampo(formLogin, $(email ? "senha" : "email"), "Preencha e-mail e senha.");

      const btn = $("btn-entrar");
      btn.disabled = true;
      btn.textContent = "Entrando…";
      try {
        const r = await entrar(email, senha);
        JB.aviso($("aviso"), `Bem-vindo, ${r.usuario.nome.split(" ")[0]}!`, "sucesso");
        const proxima = r.usuario.role === "Admin" && !volta ? "admin.html" : destino;
        // Página aberta fora da API (Live Server): segue para a loja servida pela API, já logado
        setTimeout(() => JB.FORA_DA_API ? JB.abrirNaApi(proxima, true) : (location.href = proxima), 500);
      } catch (err) {
        btn.disabled = false;
        btn.textContent = "Entrar";
        erroNoCampo(formLogin, err.status === 401 ? $("senha") : null, await mensagemDe(err));
      }
    });
  }

  // --------------------------------------------------------------- Cadastro
  const formCad = $("form-cadastro");
  if (formCad) {
    const regras = {
      tamanho: s => s.length >= 8,
      letra: s => /[A-Za-zÀ-ÿ]/.test(s),
      numero: s => /\d/.test(s)
    };
    $("senha").addEventListener("input", () => {
      const s = $("senha").value;
      document.querySelectorAll("[data-regra]").forEach(li =>
        li.classList.toggle("ok", regras[li.dataset.regra](s)));
    });

    formCad.addEventListener("submit", async e => {
      e.preventDefault();
      const nome = $("nome").value.trim();
      const email = $("email").value.trim();
      const senha = $("senha").value;

      let erro = "", campo = null;
      if (nome.split(" ").filter(Boolean).length < 2) [erro, campo] = ["Informe nome e sobrenome.", "nome"];
      else if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) [erro, campo] = ["Informe um e-mail válido.", "email"];
      else if (!Object.values(regras).every(r => r(senha))) [erro, campo] = ["A senha precisa de 8+ caracteres, com letras e números.", "senha"];
      else if (senha !== $("confirmar").value) [erro, campo] = ["As senhas não conferem.", "confirmar"];
      else if (!$("lgpd").checked) [erro, campo] = ["Aceite a Política de Privacidade para continuar.", "lgpd"];
      if (erro) return erroNoCampo(formCad, $(campo), erro);

      const btn = $("btn-cadastrar");
      btn.disabled = true;
      btn.textContent = "Criando conta…";
      try {
        await JB.conexao.quandoNoAr(() =>
          JB.api("/api/auth/cadastro", { metodo: "POST", corpo: { nome, email, senha, aceiteLgpd: true } }), avisoEspera);
        await entrar(email, senha);
        JB.aviso($("aviso"), "Conta criada! Redirecionando…", "sucesso");
        setTimeout(() => JB.FORA_DA_API ? JB.abrirNaApi(destino, true) : (location.href = destino), 700);
      } catch (err) {
        btn.disabled = false;
        btn.textContent = "Criar conta";
        const msg = await mensagemDe(err);
        erroNoCampo(formCad, /e-mail/i.test(msg) ? $("email") : null, msg);
      }
    });
  }
})();
