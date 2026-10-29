// ============================================================================
// LOJA — catálogo com categorias, filtro por linha, busca e cache offline.
// ============================================================================
import 'package:flutter/material.dart';

import '../modelos/modelos.dart';
import '../servicos/api_cliente.dart';
import '../servicos/servicos.dart';
import '../widgets/comum.dart';
import 'produto_tela.dart';

class LojaTela extends StatefulWidget {
  const LojaTela({super.key});

  @override
  State<LojaTela> createState() => _LojaTelaState();
}

class _LojaTelaState extends State<LojaTela> {
  static const categorias = [
    ('', 'Tudo'),
    ('temporada-2026', 'Temporada 2026'),
    ('retro', 'Retrô'),
    ('chuteiras', 'Chuteiras'),
  ];
  static const linhasPorCategoria = {
    'chuteiras': ['Campo', 'Society', 'Futsal'],
    'temporada-2026': ['Clube', 'Seleção'],
    'retro': ['Clube', 'Seleção'],
  };

  String _categoria = '';
  String _linha = '';
  String _busca = '';
  String _ordem = 'relevancia';
  bool _carregando = true;
  bool _offline = false;
  String? _erro;
  List<Produto> _produtos = [];
  final _buscaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final (lista, doCache) =
          await catalogo.listar(categoria: _categoria, linha: _linha, busca: _busca, ordem: _ordem);
      if (!mounted) return;
      setState(() {
        _produtos = lista;
        _offline = doCache;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _abrir(Produto p) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProdutoTela(produtoId: p.id)));
    _carregar(); // estoque pode ter mudado
  }

  @override
  Widget build(BuildContext context) {
    final linhas = linhasPorCategoria[_categoria] ?? const <String>[];
    return Scaffold(
      appBar: AppBar(
        title: Image.asset('assets/logo.png', height: 34, semanticLabel: 'Joga Bonito'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Ordenar',
            icon: const Icon(Icons.sort),
            initialValue: _ordem,
            onSelected: (v) {
              _ordem = v;
              _carregar();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'relevancia', child: Text('Mais relevantes')),
              PopupMenuItem(value: 'menor-preco', child: Text('Menor preço')),
              PopupMenuItem(value: 'maior-preco', child: Text('Maior preço')),
              PopupMenuItem(value: 'avaliacao', child: Text('Mais bem avaliados')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        color: Cores.amarelo,
        onRefresh: _carregar,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _buscaCtrl,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Buscar time, seleção, ano...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _busca.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpar busca',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _buscaCtrl.clear();
                              _busca = '';
                              _carregar();
                            }),
                  ),
                  onSubmitted: (v) {
                    _busca = v.trim();
                    _carregar();
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final (slug, nome) in categorias)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(nome),
                          selected: _categoria == slug,
                          onSelected: (_) {
                            _categoria = slug;
                            _linha = '';
                            _carregar();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (linhas.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Wrap(spacing: 8, children: [
                    for (final l in ['', ...linhas])
                      FilterChip(
                        label: Text(l.isEmpty ? 'Todas' : l),
                        selected: _linha == l,
                        onSelected: (_) {
                          _linha = l;
                          _carregar();
                        },
                      ),
                  ]),
                ),
              ),
            if (_offline)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFFFB547), borderRadius: BorderRadius.circular(8)),
                  child: const Text('Sem conexão: mostrando o catálogo salvo no aparelho.',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
                ),
              ),
            if (_carregando)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: Cores.amarelo)))
            else if (_erro != null)
              SliverFillRemaining(
                child: EstadoVazio(
                  icone: Icons.wifi_off,
                  mensagem: _erro!,
                  acao: OutlinedButton(onPressed: _carregar, child: const Text('Tentar de novo')),
                ),
              )
            else if (_produtos.isEmpty)
              const SliverFillRemaining(child: EstadoVazio(icone: Icons.search_off, mensagem: 'Nenhum produto encontrado.'))
            else
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    childAspectRatio: 0.62,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => CardProduto(produto: _produtos[i], onTap: () => _abrir(_produtos[i])),
                    childCount: _produtos.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
