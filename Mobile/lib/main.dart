// ============================================================================
// JOGA BONITO — Aplicativo Mobile (Flutter)
// PIM IV · UNIP 2026/2 · Integra-se à mesma API REST .NET 8 do site.
//
// Fluxo de navegação:
//   Splash → [Loja | Carrinho | Pedidos | Perfil]  (barra inferior)
//   Loja → Produto → (adiciona) → Carrinho → Login (se preciso) → Checkout → Pedidos
// ============================================================================
import 'package:flutter/material.dart';

import 'servicos/api_cliente.dart';
import 'servicos/servicos.dart';
import 'telas/carrinho_tela.dart';
import 'telas/loja_tela.dart';
import 'telas/pedidos_tela.dart';
import 'telas/perfil_tela.dart';
import 'widgets/comum.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JogaBonitoApp());
}

class JogaBonitoApp extends StatelessWidget {
  const JogaBonitoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Joga Bonito',
        debugShowCheckedModeBanner: false,
        theme: temaJogaBonito(),
        home: const SplashTela(),
      );
}

/// Carrega configuração, sessão salva e carrinho antes de abrir a loja.
class SplashTela extends StatefulWidget {
  const SplashTela({super.key});

  @override
  State<SplashTela> createState() => _SplashTelaState();
}

class _SplashTelaState extends State<SplashTela> {
  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    await ApiCliente.instancia.carregarConfiguracao();
    await Future.wait([sessao.restaurar(), carrinho.carregar()]);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const EstruturaPrincipal()));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Cores.verde,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/escudo.png', width: 140, semanticLabel: 'Joga Bonito'),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: Cores.amarelo),
          ]),
        ),
      );
}

/// Barra de navegação inferior com as 4 áreas do app.
class EstruturaPrincipal extends StatefulWidget {
  const EstruturaPrincipal({super.key});

  static void irPara(BuildContext context, int aba) =>
      context.findAncestorStateOfType<_EstruturaPrincipalState>()?.mudarAba(aba);

  @override
  State<EstruturaPrincipal> createState() => _EstruturaPrincipalState();
}

class _EstruturaPrincipalState extends State<EstruturaPrincipal> {
  int _aba = 0;
  int _versaoPedidos = 0; // força recarregar pedidos ao voltar para a aba

  void mudarAba(int aba) => setState(() {
        _aba = aba;
        if (aba == 2) _versaoPedidos++;
      });

  @override
  Widget build(BuildContext context) {
    final telas = [
      const LojaTela(),
      const CarrinhoTela(),
      PedidosTela(key: ValueKey(_versaoPedidos)),
      const PerfilTela(),
    ];
    return Scaffold(
      body: IndexedStack(index: _aba, children: telas),
      bottomNavigationBar: ListenableBuilder(
        listenable: carrinho,
        builder: (context, _) => NavigationBar(
          selectedIndex: _aba,
          onDestinationSelected: mudarAba,
          destinations: [
            const NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Loja'),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: carrinho.quantidade > 0,
                label: Text('${carrinho.quantidade}'),
                child: const Icon(Icons.shopping_cart_outlined),
              ),
              selectedIcon: const Icon(Icons.shopping_cart),
              label: 'Carrinho',
            ),
            const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Pedidos'),
            const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Perfil'),
          ],
        ),
      ),
    );
  }
}
