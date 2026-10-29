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
Decisão em `Maestro/docs/adr/003-app-testado-em-celular-real.md`. PC e celular na mesma rede Wi-Fi.

Preparar o celular (uma vez):
1. Configurações › Sobre o telefone › tocar 7 vezes em **Número da versão** (ativa as Opções do desenvolvedor).
2. Configurações › Sistema › **Opções do desenvolvedor** › ligar **Depuração USB**.
3. Ligar o cabo USB no PC e aceitar "Permitir depuração USB" no celular.
4. No PC: `adb devices` mostra o aparelho como `device` (não `unauthorized`).

Rodar:
1. Parar a loja, se estiver ligada (`parar-projeto.bat`), e subir aberta para a rede: `iniciar-projeto.bat -Rede`.
   Na primeira vez o Windows pergunta sobre o Firewall: permitir só em **Redes privadas**.
2. Descobrir o IP do PC: `ipconfig` › "Endereço IPv4" do Wi-Fi (ex.: `192.168.0.10`).
3. Na pasta `Mobile`: `flutter run --dart-define=API_URL=http://IP-DO-PC:5000`.

Verificar:
- [ ] O app abre, mostra os 36 produtos e as fotos.
- [ ] Login com `matheus@estudante.com` / `Cliente@2026`.
- [ ] Compra pelo app (Pix): aparece em *Meus pedidos* no app **e** no site (`http://localhost:5000`, mesma conta).
- [ ] No painel admin do site, o pedido do app tem origem **Mobile**; um pedido feito no site tem origem **Web**.
- [ ] Cancelar pelo site um pedido feito no app: o estoque do tamanho volta (ver na página do produto, no app).
- [ ] Desligar o Wi-Fi do celular: o app mostra aviso de sem conexão, sem travar. Religar: volta a funcionar.
- [ ] Rodar o roteiro 1 (TalkBack) neste mesmo aparelho.
- [ ] Ao terminar: `parar-projeto.bat` e `iniciar-projeto.bat` sem `-Rede` (a loja volta a aceitar só este PC).

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
