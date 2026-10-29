# Joga Bonito — App Mobile (Flutter)

App Android/iOS da loja, integrado à **mesma API REST .NET 8** do site: login JWT, catálogo, carrinho, checkout e pedidos sincronizados (um pedido feito no app aparece no site e vice-versa).

## Telas e fluxo

```
Splash ──► Loja ──► Produto ──► (adiciona) ──► Carrinho ──► Login* ──► Checkout ──► Pedidos
            │                                                    * só se não estiver logado
            └── barra inferior: Loja · Carrinho · Pedidos · Perfil
```

| Tela | O que faz |
|---|---|
| Loja | Categorias (Temporada 2026, Retrô, Chuteiras), filtro por linha (Clube/Seleção, Campo/Society/Futsal), busca, ordenação, puxar para atualizar |
| Produto | Galeria deslizável, tamanhos com estoque real (esgotados desabilitados), guia de medidas, quantidade |
| Carrinho | Itens salvos no aparelho, barra de frete grátis |
| Checkout | Endereço, Pix/crédito (até 6x)/débito, cupom; valores confirmados pela API |
| Pedidos | Histórico com linha do tempo de status, cancelamento antes da separação |
| Perfil | Conta, endereço do servidor da API, data da última sincronização |

**Sincronização:** o catálogo completo fica em cache (`shared_preferences`); sem internet o app mostra a última versão salva. Carrinho e sessão (token JWT com validade) também ficam no aparelho.

## Como rodar

O repositório traz só o código (`lib/`, `test/`, `assets/`, `tool/`). Gere as pastas de plataforma uma vez:

```bash
cd Mobile
flutter create --project-name jogabonito_mobile --org br.unip.pim --platforms android,ios .
flutter pub get
dart run tool/preparar_android.dart     # HTTP só na depuração; remove o teste de exemplo do flutter create
flutter test
flutter run
```

| Onde roda | Endereço da API |
|---|---|
| Emulador Android | padrão `http://10.0.2.2:5000` (o PC) — suba a API com `iniciar-projeto.bat` |
| Celular físico, rede local | `iniciar-projeto.bat -Rede` no PC; no app, *Perfil › Servidor da API* → `http://IP-DO-PC:5000` (só em `flutter run`, depuração) |
| APK de produção | `flutter build apk --release --dart-define=API_URL=https://<loja>.azurewebsites.net` |

O app só aceita HTTP para endereços da rede local; fora dela exige HTTPS. No APK de produção o próprio Android também bloqueia HTTP (o `preparar_android.dart` libera HTTP apenas no build de depuração). No iPhone, para testar contra o PC, adicione `NSAllowsLocalNetworking` em `ios/Runner/Info.plist`.

O pipeline gera o APK de produção com a variável `URL_LOJA` do GitHub (artefato **app-android**).

Conta de demonstração: `matheus@estudante.com` / `Cliente@2026`.

## Estrutura

```
lib/
├── main.dart              app, splash e navegação inferior
├── modelos/modelos.dart   Usuario, Produto, ItemCarrinho, Pedido... (fromJson/toJson)
├── servicos/
│   ├── api_cliente.dart   HTTP + token JWT + tradução de erros
│   └── servicos.dart      Sessão, Carrinho (ChangeNotifier), Catálogo com cache, Pedidos
├── telas/                 loja, produto, carrinho/checkout, pedidos, login, perfil
└── widgets/comum.dart     tema verde/amarelo, formatação R$, card de produto
```
