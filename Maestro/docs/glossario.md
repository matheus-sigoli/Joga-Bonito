# Glossário — Joga Bonito

| Termo | Significado no projeto |
|---|---|
| **Loja** | A API .NET (`Site/backend`) servindo também as páginas do site, em `http://localhost:5000` no PC ou no App Service do Azure. |
| **Site público** | Versão estática do site (`publico/`, gerada por `publicar_estatico.py`) publicada na Vercel em **https://joga-bonito-sigma.vercel.app** (o GitHub Pages não está ativado). Roda em **modo demonstração**, sem API nem banco. Os endereços de cada implantação (`joga-bonito-<código>-matheus-sigoli.vercel.app`) pedem login da Vercel; o endereço principal é aberto. |
| **Modo demonstração** | Funcionamento sem servidor: catálogo de `catalogo-local.js` e pedidos guardados só no navegador. |
| **Pagamento simulado** | Pix e cartão de mentira: nenhum valor é cobrado e os dados do cartão não são enviados. Todo checkout mostra esse aviso. |
| **Joga Junto** | Programa social: 1% do valor dos produtos com desconto (`Subtotal − Desconto`) de cada pedido, calculado por `dbo.fn_CalcularJogaJunto` e gravado em `Pedidos.ValorJogaJunto`. |
| **Origem do pedido** | `Web` (site) ou `Mobile` (app). Os dois gravam no mesmo banco e aparecem no mesmo histórico. |
| **Contas de demonstração** | `admin@jogabonito.com`, `matheus@estudante.com` e `professor@unip.br`, criadas pelo `demo.sql` só em Development. Nunca existem em produção. |
| **Conferência do banco** | `Site/banco/conferencia.sql`: 23 regras de consistência, só leitura. Em Development, a regra 23 falha de propósito. |
| **Moderação** | Avaliação com link fica **Pendente** até um administrador publicar; ocultar exige motivo (`sp_ModerarAvaliacao`). |
| **Exclusão de conta (LGPD)** | O cliente confirma a senha; nome, e-mail e endereço são anonimizados (`sp_AnonimizarUsuario`) e os pedidos ficam no histórico sem dados pessoais. |
| **Endereço cifrado** | Rua, número etc. gravados com AES-256-GCM pela API, com prefixo `enc1:`. |
| **Build de depuração** | App gerado por `flutter run`: aceita HTTP na rede local para falar com a loja no PC. |
| **APK de produção** | `flutter build apk --release`: só aceita HTTPS, ou seja, precisa da loja publicada. |
| **ADR** | Registro de decisão do projeto (`Maestro/docs/adr/`). |
