// ============================================================================
// PRODUTO — galeria, tamanho com estoque real, quantidade e guia de medidas.
// ============================================================================
import 'package:flutter/material.dart';

import '../modelos/modelos.dart';
import '../servicos/api_cliente.dart';
import '../servicos/servicos.dart';
import '../widgets/comum.dart';

class ProdutoTela extends StatefulWidget {
  final int produtoId;
  const ProdutoTela({super.key, required this.produtoId});

  @override
  State<ProdutoTela> createState() => _ProdutoTelaState();
}

class _ProdutoTelaState extends State<ProdutoTela> {
  ProdutoDetalhe? _d;
  String? _erro;
  String? _tamanho;
  int _qtd = 1;
  int _foto = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final d = await catalogo.detalhe(widget.produtoId);
      if (mounted) setState(() => _d = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    }
  }

  int _estoque(String t) => _d!.tamanhos.firstWhere((x) => x.tamanho == t, orElse: () => TamanhoEstoque(t, 0)).quantidade;

  Future<void> _adicionar() async {
    if (_tamanho == null) {
      mostrarMensagem(context, 'Escolha um tamanho primeiro.', erro: true);
      return;
    }
    final p = _d!.produto;
    final jaNoCarrinho =
        carrinho.itens.where((i) => i.produtoId == p.id && i.tamanho == _tamanho).firstOrNull?.quantidade ?? 0;
    if (jaNoCarrinho + _qtd > _estoque(_tamanho!)) {
      mostrarMensagem(context, 'Só há ${_estoque(_tamanho!)} unidade(s) desse tamanho.', erro: true);
      return;
    }
    await carrinho.adicionar(p, _tamanho!, _qtd);
    if (mounted) mostrarMensagem(context, '${p.nome} ($_tamanho) adicionado ao carrinho ⚽');
  }

  void _guiaMedidas() {
    final chuteira = _d!.tipo == 'Chuteira';
    final linhas = chuteira
        ? const [['37', '24,0 cm'], ['38', '24,7 cm'], ['39', '25,3 cm'], ['40', '26,0 cm'],
                 ['41', '26,7 cm'], ['42', '27,3 cm'], ['43', '28,0 cm'], ['44', '28,7 cm']]
        : const [['P', '50 × 70 cm'], ['M', '53 × 72 cm'], ['G', '56 × 74 cm'], ['GG', '59 × 76 cm'], ['XG', '62 × 78 cm']];
    showModalBottomSheet(
      context: context,
      backgroundColor: Cores.superficie,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(chuteira ? 'Guia de numeração' : 'Guia de medidas',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(chuteira ? 'Comprimento do pé (calcanhar ao dedão)' : 'Largura × altura da camisa',
              style: const TextStyle(color: Cores.textoSuave)),
          const SizedBox(height: 12),
          for (final l in linhas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(width: 48, child: Text(l[0], style: const TextStyle(fontWeight: FontWeight.w800, color: Cores.amarelo))),
                Text(l[1]),
              ]),
            ),
          const SizedBox(height: 10),
          const Text('A primeira troca de tamanho é grátis em até 30 dias.', style: TextStyle(color: Cores.textoSuave)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_erro != null) {
      return Scaffold(appBar: AppBar(), body: EstadoVazio(icone: Icons.error_outline, mensagem: _erro!));
    }
    if (_d == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator(color: Cores.amarelo)));
    }
    final p = _d!.produto;
    final imagens = _d!.imagens.isEmpty ? [p.img] : _d!.imagens;
    final esgotado = _d!.tamanhos.every((t) => t.quantidade == 0);

    return Scaffold(
      appBar: AppBar(title: Text(p.categoria)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: PageView.builder(
              itemCount: imagens.length,
              onPageChanged: (i) => setState(() => _foto = i),
              itemBuilder: (_, i) => Semantics(
                  label: '${p.nome}, foto ${i + 1} de ${imagens.length}', child: ImagemProduto(imagens[i])),
            ),
          ),
          if (imagens.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < imagens.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _foto ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: i == _foto ? Cores.amarelo : Colors.white24, borderRadius: BorderRadius.circular(3)),
                  ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.rotulo.toUpperCase(),
                  style: const TextStyle(color: Cores.amarelo, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
              const SizedBox(height: 6),
              Text(p.nome, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              if (p.totalAvaliacoes > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('★ ${p.notaMedia.toStringAsFixed(1)} · ${p.totalAvaliacoes} avaliação(ões)',
                      style: const TextStyle(color: Cores.amarelo)),
                ),
              const SizedBox(height: 14),
              if (p.emPromocao)
                Text(brl(p.preco),
                    style: const TextStyle(decoration: TextDecoration.lineThrough, color: Cores.textoSuave)),
              Text(brl(p.precoFinal),
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Cores.amarelo)),
              Text('ou 6x de ${brl(p.precoFinal / 6)} sem juros', style: const TextStyle(color: Cores.textoSuave)),
              const SizedBox(height: 20),
              Row(children: [
                Text(_d!.tipo == 'Chuteira' ? 'Numeração' : 'Tamanho',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton(onPressed: _guiaMedidas, child: const Text('Guia de medidas')),
              ]),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in _d!.tamanhos)
                  // Leitor de tela (TalkBack/VoiceOver): "Tamanho M, 12 em estoque, selecionado"
                  Semantics(
                    label: '${_d!.tipo == 'Chuteira' ? 'Numeração' : 'Tamanho'} ${t.tamanho}, '
                        '${t.quantidade == 0 ? 'esgotado' : '${t.quantidade} em estoque'}',
                    selected: _tamanho == t.tamanho,
                    excludeSemantics: true,
                    button: true,
                    enabled: t.quantidade > 0,
                    onTap: t.quantidade == 0 ? null : () => setState(() {
                      _tamanho = t.tamanho;
                      _qtd = _qtd.clamp(1, t.quantidade);
                    }),
                    child: ChoiceChip(
                    label: Text(t.tamanho),
                    selected: _tamanho == t.tamanho,
                    tooltip: t.quantidade == 0 ? 'Esgotado' : null,
                    onSelected: t.quantidade == 0
                        ? null
                        : (_) => setState(() {
                              _tamanho = t.tamanho;
                              _qtd = _qtd.clamp(1, t.quantidade);
                            }),
                  ),
                  ),
              ]),
              if (_tamanho != null && _estoque(_tamanho!) < 5)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Últimas ${_estoque(_tamanho!)} unidade(s) neste tamanho',
                      style: const TextStyle(color: Color(0xFFFFB547), fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 18),
              Row(children: [
                const Text('Quantidade', style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton.outlined(
                  tooltip: 'Diminuir',
                  onPressed: _qtd > 1 ? () => setState(() => _qtd--) : null,
                  icon: const Icon(Icons.remove),
                ),
                Semantics(
                  liveRegion: true,
                  label: 'Quantidade: $_qtd',
                  excludeSemantics: true,
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text('$_qtd', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                ),
                IconButton.outlined(
                  tooltip: 'Aumentar',
                  onPressed: _qtd < (_tamanho == null ? 10 : _estoque(_tamanho!).clamp(1, 10))
                      ? () => setState(() => _qtd++)
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ]),
              const SizedBox(height: 20),
              const Text('Descrição', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(p.descricao, style: const TextStyle(color: Cores.textoSuave, height: 1.5)),
              const SizedBox(height: 16),
              const Text('🚚 Frete grátis acima de R\$ 299  ·  🔁 Troca em 30 dias',
                  style: TextStyle(color: Cores.textoSuave, fontSize: 12)),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: esgotado ? null : _adicionar,
            icon: const Icon(Icons.add_shopping_cart),
            label: Text(esgotado ? 'ESGOTADO' : 'ADICIONAR AO CARRINHO'),
          ),
        ),
      ),
    );
  }
}
