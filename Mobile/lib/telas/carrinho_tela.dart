// ============================================================================
// CARRINHO e CHECKOUT — valores confirmados pela API (/api/pedidos/simular).
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../modelos/modelos.dart';
import '../servicos/api_cliente.dart';
import '../servicos/servicos.dart';
import '../widgets/comum.dart';
import 'login_tela.dart';

class CarrinhoTela extends StatelessWidget {
  const CarrinhoTela({super.key});

  Future<void> _finalizar(BuildContext context) async {
    if (!sessao.logado) {
      final entrou = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LoginTela()));
      if (entrou != true || !context.mounted) return;
    }
    final concluido =
        await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CheckoutTela()));
    if (concluido == true && context.mounted) EstruturaPrincipal.irPara(context, 2);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Carrinho')),
        body: ListenableBuilder(
          listenable: carrinho,
          builder: (context, _) {
            if (carrinho.itens.isEmpty) {
              return EstadoVazio(
                icone: Icons.shopping_cart_outlined,
                mensagem: 'Seu carrinho está vazio.',
                acao: FilledButton(
                  onPressed: () => EstruturaPrincipal.irPara(context, 0),
                  style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
                  child: const Text('IR PARA A LOJA'),
                ),
              );
            }
            final falta = CarrinhoServico.limiteFreteGratis - carrinho.subtotal;
            return Column(children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: carrinho.itens.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _ItemTile(item: carrinho.itens[i]),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: const BoxDecoration(
                  color: Cores.superficie,
                  border: Border(top: BorderSide(color: Color(0x24FCCA0F))),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(
                      falta > 0 ? 'Faltam ${brl(falta)} para o frete grátis' : '🎉 Frete grátis garantido',
                      style: const TextStyle(color: Cores.textoSuave),
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: (carrinho.subtotal / CarrinhoServico.limiteFreteGratis).clamp(0.0, 1.0),
                      color: Cores.amarelo,
                      backgroundColor: Cores.superficie2,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    const SizedBox(height: 12),
                    _linhaValor('Subtotal', brl(carrinho.subtotal)),
                    _linhaValor('Frete (estimado)', carrinho.freteEstimado == 0 ? 'Grátis' : brl(carrinho.freteEstimado)),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () => _finalizar(context), child: const Text('FINALIZAR COMPRA')),
                  ]),
                ),
              ),
            ]);
          },
        ),
      );
}

Widget _linhaValor(String rotulo, String valor, {bool destaque = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Text(rotulo, style: TextStyle(color: destaque ? Colors.white : Cores.textoSuave, fontWeight: destaque ? FontWeight.w800 : null)),
        const Spacer(),
        Text(valor,
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: destaque ? 20 : 14,
                color: destaque ? Cores.amarelo : Colors.white)),
      ]),
    );

class _ItemTile extends StatelessWidget {
  final ItemCarrinho item;
  const _ItemTile({required this.item});

  @override
  Widget build(BuildContext context) => Card(
        color: Cores.superficie,
        elevation: 0,
        shape: formaCard,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: 72, height: 72, child: ImagemProduto(item.img)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.nome, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('Tamanho ${item.tamanho} · ${brl(item.preco)}', style: const TextStyle(color: Cores.textoSuave, fontSize: 12)),
                Row(children: [
                  IconButton(
                    tooltip: item.quantidade == 1 ? 'Remover ${item.nome}' : 'Diminuir ${item.nome}',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => carrinho.alterar(item, item.quantidade - 1),
                    icon: Icon(item.quantidade == 1 ? Icons.delete_outline : Icons.remove),
                  ),
                  Semantics(
                    label: 'Quantidade: ${item.quantidade}',
                    excludeSemantics: true,
                    child: Text('${item.quantidade}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: 'Aumentar ${item.nome}',
                    visualDensity: VisualDensity.compact,
                    onPressed: item.quantidade < 10 ? () => carrinho.alterar(item, item.quantidade + 1) : null,
                    icon: const Icon(Icons.add),
                  ),
                  const Spacer(),
                  Text(brl(item.subtotal), style: const TextStyle(color: Cores.amarelo, fontWeight: FontWeight.w800)),
                ]),
              ]),
            ),
          ]),
        ),
      );
}

// ----------------------------------------------------------------------------
// CHECKOUT: endereço → pagamento → confirmação
// ----------------------------------------------------------------------------
class CheckoutTela extends StatefulWidget {
  const CheckoutTela({super.key});

  @override
  State<CheckoutTela> createState() => _CheckoutTelaState();
}

class _CheckoutTelaState extends State<CheckoutTela> {
  final _form = GlobalKey<FormState>();
  final _c = {
    for (final k in ['cep', 'rua', 'numero', 'complemento', 'bairro', 'cidade', 'uf', 'cupom']) k: TextEditingController()
  };
  String _forma = 'PIX';
  int _parcelas = 1;
  ResumoPedido? _resumo;
  String? _cupomAplicado;
  String? _erro;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _simular();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _simular([String? cupom]) async {
    try {
      final r = await pedidos.simular(carrinho.paraApi(), cupom);
      if (!mounted) return;
      setState(() {
        _resumo = r;
        _cupomAplicado = r.cupom;
        _erro = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    }
  }

  Future<void> _confirmar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final r = await pedidos.criar(
        itens: carrinho.paraApi(),
        formaPagamento: _forma,
        parcelas: _forma == 'Cartão de Crédito' ? _parcelas : 1,
        cupom: _cupomAplicado,
        endereco: {
          'cep': _c['cep']!.text.replaceAll(RegExp(r'\D'), ''),
          'rua': _c['rua']!.text.trim(),
          'numero': _c['numero']!.text.trim(),
          'complemento': _c['complemento']!.text.trim().isEmpty ? null : _c['complemento']!.text.trim(),
          'bairro': _c['bairro']!.text.trim(),
          'cidade': _c['cidade']!.text.trim(),
          'estado': _c['uf']!.text.trim().toUpperCase(),
        },
      );
      await carrinho.limpar();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: Cores.superficie,
          title: const Text('Pedido confirmado!'),
          content: Text('Pedido #${r['pedidoId']} · ${brl((r['total'] as num).toDouble())}\n'
              'Rastreio: ${r['codigoRastreio']}\n'
              '${(r['jogaJunto'] as num? ?? 0) > 0 ? 'Joga Junto: ${brl((r['jogaJunto'] as num).toDouble())} para escolinhas de futebol.\n' : ''}'
              '\nPagamento simulado: nenhuma cobrança foi feita.\nAcompanhe em "Pedidos" — no app ou no site.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('VER MEUS PEDIDOS'))],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  String? _obrigatorio(String? v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null;

  Widget _campo(String chave, String rotulo,
          {TextInputType? teclado, String? Function(String?)? validar, int? max, List<TextInputFormatter>? fmt}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: _c[chave],
          decoration: InputDecoration(labelText: rotulo, counterText: ''),
          keyboardType: teclado,
          maxLength: max,
          inputFormatters: fmt,
          validator: validar,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final total = _resumo?.total ?? carrinho.subtotal;
    return Scaffold(
      appBar: AppBar(title: const Text('Finalizar compra')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Entrega', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          _campo('cep', 'CEP', teclado: TextInputType.number, max: 8,
              fmt: [FilteringTextInputFormatter.digitsOnly],
              validar: (v) => (v ?? '').length == 8 ? null : 'CEP com 8 dígitos'),
          _campo('rua', 'Rua', validar: _obrigatorio, max: 150),
          Row(children: [
            Expanded(child: _campo('numero', 'Número', validar: _obrigatorio, max: 20)),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: _campo('complemento', 'Complemento', max: 60)),
          ]),
          _campo('bairro', 'Bairro', validar: _obrigatorio, max: 100),
          Row(children: [
            Expanded(flex: 3, child: _campo('cidade', 'Cidade', validar: _obrigatorio, max: 100)),
            const SizedBox(width: 10),
            Expanded(
                child: _campo('uf', 'UF', max: 2,
                    validar: (v) => RegExp(r'^[A-Za-z]{2}$').hasMatch(v ?? '') ? null : 'UF')),
          ]),
          const SizedBox(height: 10),
          const Text('Pagamento', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'PIX', label: Text('Pix'), icon: Icon(Icons.bolt)),
              ButtonSegment(value: 'Cartão de Crédito', label: Text('Crédito'), icon: Icon(Icons.credit_card)),
              ButtonSegment(value: 'Cartão de Débito', label: Text('Débito')),
            ],
            selected: {_forma},
            onSelectionChanged: (s) => setState(() => _forma = s.first),
          ),
          if (_forma == 'Cartão de Crédito')
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: DropdownButtonFormField<int>(
                initialValue: _parcelas,
                decoration: const InputDecoration(labelText: 'Parcelas'),
                items: [
                  for (var n = 1; n <= 6; n++)
                    if (n == 1 || total / n >= 30)
                      DropdownMenuItem(value: n, child: Text('${n}x de ${brl(total / n)} sem juros')),
                ],
                onChanged: (v) => setState(() => _parcelas = v ?? 1),
              ),
            ),
          if (_forma == 'PIX')
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Após confirmar, o código Pix é gerado e o pedido aprovado na hora (pagamento simulado).',
                  style: TextStyle(color: Cores.textoSuave)),
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('🔒 Ambiente acadêmico: pagamento simulado, nenhum dado de cartão é enviado.',
                  style: TextStyle(color: Cores.textoSuave)),
            ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _c['cupom'],
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Cupom de desconto'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => _simular(_c['cupom']!.text.trim().toUpperCase()),
              child: const Text('Aplicar'),
            ),
          ]),
          if (_cupomAplicado != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Cupom $_cupomAplicado aplicado ✔', style: const TextStyle(color: Cores.sucesso)),
            ),
          const SizedBox(height: 16),
          if (_resumo != null) ...[
            _linhaValor('Subtotal', brl(_resumo!.subtotal)),
            if (_resumo!.desconto > 0) _linhaValor('Desconto', '− ${brl(_resumo!.desconto)}'),
            _linhaValor('Frete', _resumo!.frete == 0 ? 'Grátis' : brl(_resumo!.frete)),
            const Divider(),
            _linhaValor('Total', brl(_resumo!.total), destaque: true),
            if (_resumo!.jogaJunto > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${brl(_resumo!.jogaJunto)} deste pedido vão para escolinhas de futebol (Joga Junto).',
                    style: const TextStyle(color: Cores.sucesso, fontSize: 12)),
              ),
          ],
          if (_erro != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0x22FF7A7A), borderRadius: BorderRadius.circular(8)),
              child: Text(_erro!, style: const TextStyle(color: Cores.erro)),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _enviando || _resumo == null ? null : _confirmar,
            child: _enviando
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text('CONFIRMAR · ${brl(total)}'),
          ),
        ]),
      ),
    );
  }
}
