# ADR 009 — App no celular conecta na loja do PC (rede local)

**Data:** 10/11/2026 · **Situação:** aceita e aplicada

## Contexto
A Etapa 5 do manual (2,0 pontos) pede um app integrado à mesma API e ao mesmo banco do site.
O app Flutter já estava pronto (6 telas, token no cofre seguro, catálogo offline, pedidos com
origem `Mobile`), mas o teste num celular real (ADR 003, roteiro 5) não tinha sido feito porque a
ligação celular → PC não funcionava sem muito passo manual:

| Ponto | Problema |
|---|---|
| Lançador | `-Rede` existia, mas nenhum `.bat` usava; se a API já tinha ligado com o Windows (só `localhost`), o `-Rede` dizia "já está no ar" e não reabria para a rede. |
| Windows | Firewall bloqueia a porta 5000; Wi-Fi marcado como "Rede pública" bloqueia tudo. |
| App | Era preciso descobrir o IP do PC (`ipconfig`) e digitar em Perfil. |
| APK | O APK do pipeline só aceita HTTPS e apontava para o emulador: no celular real só funcionava com `flutter run` e cabo. |
| Site público | A Vercel roda a loja no navegador, sem API: não serve para o app. |
| Banco | Já pronto: `Pedidos.Origem` ('Web' / 'Mobile', com CHECK) e `sp_RegistrarPedido @Origem`. |

O app **nunca** acessa o banco diretamente: tudo passa pela API (regras, estoque e segurança iguais ao site).

## Decisão
1. **`iniciar-com-celular.bat`** (`jogabonito.ps1 -Rede`):
   - religa a API em `0.0.0.0` se ela estava só em `localhost` (o endereço fica em `api-endereco.txt`);
   - cria a regra de firewall *Joga Bonito - API (rede local)*: TCP 5000, perfis Privado/Domínio,
     **só `LocalSubnet`** (pede administrador uma vez);
   - avisa se o Wi-Fi está como Rede pública e oferece marcar como privada;
   - mostra `CELULAR http://IP:5000` com os IPv4 privados das placas reais (ignora WSL, Hyper-V, VirtualBox, VMware e Docker);
   - o modo fica lembrado (`modo-rede.txt`), inclusive no início com o Windows; `iniciar-projeto.bat -SemRede` desfaz.
2. **API:** `GET /api/loja` → `{"loja": "Joga Bonito", ...}` identifica a loja.
3. **App:** *Conectar à loja* (Perfil e tela de sem conexão) com **Procurar a loja na rede**: pega o IP do
   celular, testa `http://IP:5000/api/loja` na mesma rede /24 (32 por vez, 0,9 s cada) e salva o primeiro que
   responder como Joga Bonito. Também aceita o endereço digitado, mas só salva depois de confirmar `/api/loja`.
4. **APK rede local** (artefato `app-android-rede-local`): `preparar_android.dart --rede-local` libera HTTP no
   Android. O próprio app continua recusando HTTP fora das redes privadas (`ApiCliente.normalizarServidor`), então
   senha e token só trafegam sem TLS dentro da rede local. O APK de produção (`app-android`) continua só HTTPS.
5. **Funções que só o site tinha:** avaliações (ver e enviar, com a mesma moderação), busca de CEP (ViaCEP) e
   *Meus dados (LGPD)* no Perfil.
6. **Banco:** view `vw_VendasPorCanal` (Web × Mobile, pedidos não cancelados), card **Vendas por canal** no painel,
   consulta `vendas-por-canal` na aba Banco de dados e 2 regras novas em `conferencia.sql`.

## Consequências
- O teste no celular vira: rodar `iniciar-com-celular.bat`, instalar o APK, tocar em *Procurar*.
- HTTP na rede local é aceitável para a demonstração acadêmica (Wi-Fi de confiança, firewall só para a sub-rede).
  Em produção vale o plano Azure com HTTPS (ADR 002).
- Redes que isolam os aparelhos (Wi-Fi de visitantes, algumas redes de faculdade) não deixam o celular ver o PC:
  nesse caso, usar o roteador do celular (hotspot) com o PC conectado nele.

## Testes
- E2E `test_31`: `/api/loja`, login por token (como o app), pedido com origem Mobile e painel mostrando "App (celular)".
- `validar_loja.py` (contra a API real + SQL Server no pipeline): `/api/loja`, pedido do app com origem Mobile,
  `vendasPorCanal` com Web e Mobile.
- Flutter: `test/descoberta_test.dart` (rede /24, emulador, IP público não varrido, avaliações, CEP).
