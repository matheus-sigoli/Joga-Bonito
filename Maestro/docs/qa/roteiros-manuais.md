# Roteiros de teste manual (o que a automação não alcança)

Marque cada item e anote quem testou e em qual aparelho/navegador.

## 1. Leitor de tela no app (TalkBack no Android, VoiceOver no iOS)
Ligue o leitor (Android: Configurações › Acessibilidade › TalkBack; iPhone: Ajustes › Acessibilidade › VoiceOver).

- [ ] Loja: cada card é lido como "Nome do produto, R$ preço" e, se for o caso, "esgotado".
- [ ] Produto: os tamanhos são lidos como "Tamanho M, 12 em estoque" / "esgotado"; o selecionado é anunciado.
- [ ] Produto: "Quantidade: 2" é anunciado ao tocar em Aumentar/Diminuir.
- [ ] Carrinho: botões lidos como "Diminuir/Aumentar/Remover <produto>"; total e frete lidos em ordem.
- [ ] Checkout: rótulos dos campos de endereço e cartão são lidos; mensagem de erro é anunciada.
- [ ] Perfil: Trocar senha, Sair de todos os aparelhos e Excluir minha conta acessíveis só com gestos.
- [ ] Fonte do sistema no máximo: nenhum botão de compra fica escondido.

## 2. Site só com teclado (Tab, Shift+Tab, Enter, Espaço, setas, Esc)
- [ ] Inicial: "Pular para o conteúdo" é o primeiro foco; abas Seleções/Clubes e Campo/Society/Futsal trocam com setas.
- [ ] Produto: escolher tamanho, quantidade e "Adicionar ao carrinho"; guia de medidas abre e fecha com Esc.
- [ ] Carrinho e checkout completos (endereço, Pix) sem mouse.
- [ ] Painel admin: abas com setas/Home/End; moderar uma avaliação; ajustar estoque.
- [ ] Alto contraste e A+ (4 vezes) em todas as páginas: nada sobreposto, sem rolagem lateral.
- [ ] VLibras abre e traduz em inicial, produto, carrinho e painel admin.

## 3. Ambiente publicado (Azure)
- [ ] `python3 Site/ferramentas/verificar_publicacao.py https://<loja>` com todas as verificações OK.
- [ ] Compra feita no app aparece no site e no painel (e vice-versa), com origem "Mobile"/"Web".
- [ ] Cancelamento devolve o estoque nas duas plataformas.
- [ ] Application Insights mostra requisições e dependências SQL; alerta de 5xx chega por e-mail (forçar com URL inválida de API não basta — use o teste de alerta do Azure Monitor).
- [ ] Restauração de backup do Azure SQL para um banco de teste funciona (Portal › Banco › Restaurar).

## 4. Lançador no Windows (iniciar-projeto.bat)
Rode num Windows real: o lançador não pode ser executado no ambiente de CI (Linux).

- [ ] Primeira execução: além de abrir o login, cria o atalho "Joga Bonito" (com o ícone da loja) na área de trabalho e liga o início automático.
- [ ] Reiniciar o computador e abrir http://localhost:5000 sem rodar nada: a tela de login funciona e o botão "Cliente" entra direto.
- [ ] Abrir `Site/HTML/login.html` pelo Live Server do VS Code (127.0.0.1:5500): a página vai para http://127.0.0.1:5000 e o login continua valendo ao navegar.
- [ ] Visual Studio sem SQL Express (só LocalDB): F5 abre o login e entra (log: "usando '(localdb)\\MSSQLLocalDB'").
- [ ] Dois cliques em `iniciar-projeto.bat` com SQL Server Express ligado: a loja abre sozinha em http://localhost:5000 e **nenhuma janela preta fica aberta** (a API roda em segundo plano).
- [ ] Com o serviço `SQL Server (SQLEXPRESS)` parado: o lançador pede permissão de administrador uma vez, liga o serviço e segue.
- [ ] Só com LocalDB (Visual Studio, sem SQL Express): o lançador usa `(localdb)\MSSQLLocalDB`.
- [ ] Segunda execução com a API já ligada: só abre o navegador, sem recompilar.
- [ ] `parar-projeto.bat`: a loja mostra a faixa "Reconectando à loja"; ao rodar `iniciar-projeto.bat` de novo, a página se atualiza sozinha.
- [ ] `ligar-com-o-windows.bat`, sair e entrar no Windows: http://localhost:5000 responde sem abrir nada. `desligar-com-o-windows.bat` desfaz.
- [ ] Editar o preço de um produto em `Site/Javascript/catalogo-local.js` com a API ligada e salvar: em até 5 s o novo preço aparece na loja (e em `api.log`: "catalogo-local.js alterado").
- [ ] Abrir `Site/HTML/inicial.html` com dois cliques (file://) com a API ligada: o navegador vai para http://localhost:5000/HTML/inicial.html.
- [ ] `iniciar-projeto.bat -Rede`: o app no celular físico conecta pelo IP do PC.

## 5. App no celular Android real, ligado à loja do PC (sem Azure)
Decisões em `Maestro/docs/adr/003-app-testado-em-celular-real.md` e `009-app-conecta-na-loja-do-pc.md`.
PC e celular **na mesma rede Wi-Fi** (de casa ou da escola; não use rede de visitantes).

No PC (uma vez por teste):
1. Dar dois cliques em **`iniciar-com-celular.bat`**.
   - Na primeira vez o Windows pede permissão de administrador: **Sim** (libera a porta 5000 só para a rede local).
   - Se avisar que o Wi-Fi está como **Rede pública**, responder **S** (só em rede de confiança).
2. A janela mostra `CELULAR http://192.168.x.x:5000`: anote, caso a busca automática não ache.

Instalar o app (escolha um jeito):
- **Sem cabo:** no GitHub › Actions › último **CI-CD** verde › artefato **app-android-rede-local** › baixar,
  descompactar e abrir `joga-bonito-rede-local.apk` no celular (permitir "instalar apps desconhecidos").
- **Com cabo e Flutter no PC:** ativar Opções do desenvolvedor (7 toques em Número da versão) e Depuração USB,
  conectar o cabo e, na pasta `Mobile`, rodar `flutter run`.

Conectar:
1. Abrir o app. Sem conexão, a loja mostra **CONECTAR À LOJA** (ou Perfil › Conectar à loja).
2. Tocar em **PROCURAR A LOJA NA REDE**: em poucos segundos aparece "Conectado à loja em http://192.168.x.x:5000".
   Se não achar, digitar o endereço que a janela do PC mostrou.

Verificar:
- [ ] O app abre, mostra os 36 produtos e as fotos.
- [ ] Login com `matheus@estudante.com` / `Cliente@2026`.
- [ ] Na finalização, digitar o CEP `01310100`: rua, bairro, cidade e UF se preenchem sozinhos.
- [ ] Compra pelo app (Pix): aparece em *Meus pedidos* no app **e** no site (`http://localhost:5000`, mesma conta).
- [ ] No painel admin do site: o pedido do app tem origem **Mobile**, e **Vendas por canal** mostra "App (celular)".
- [ ] No app, abrir o produto comprado › **Avaliar** › 5 estrelas: a avaliação aparece no app e no site.
- [ ] Perfil › **Meus dados (LGPD)** mostra a conta, os pedidos e as avaliações.
- [ ] Cancelar pelo site um pedido feito no app: o estoque do tamanho volta (ver na página do produto, no app).
- [ ] Desligar o Wi-Fi do celular: o app mostra o catálogo salvo e o aviso de sem conexão, sem travar. Religar: volta.
- [ ] Rodar o roteiro 1 (TalkBack) neste mesmo aparelho.
- [ ] Ao terminar (opcional): `iniciar-projeto.bat -SemRede` volta a loja a aceitar só este PC.

## 6. Site público publicado (Vercel: https://joga-bonito-sigma.vercel.app)
Use sempre esse endereço com a banca: os endereços de cada implantação pedem login da Vercel.

- [ ] O endereço abre direto na página inicial, com fotos.
- [ ] Toda página mostra que é demonstração; o checkout mostra **Pagamento simulado**.
- [ ] Login com uma conta de demonstração, compra e pedido em *Meus pedidos* funcionam sem servidor.
- [ ] DevTools › Network: nenhuma chamada para `localhost` ou para a API.
- [ ] VLibras abre e traduz.

## 7. Segurança no navegador (DevTools › Application)
- [ ] Depois do login, `Local Storage` não tem token; `Cookies` tem `jb_sessao` com HttpOnly e SameSite=Strict.
- [ ] Em produção (HTTPS), o cookie se chama `__Host-jb_sessao` e tem Secure.
- [ ] No SSMS, `SELECT TOP 5 Rua, Cep FROM Enderecos` mostra `enc1:...`; com um login sem UNMASK, `SELECT Email FROM Usuarios` mostra `mXXX@XXXX.com`.
