// ============================================================================
// PEDIDOS — histórico sincronizado com a API (mesmos pedidos do site).
// ============================================================================
import 'package:flutter/material.dart';

import '../modelos/modelos.dart';
import '../servicos/api_cliente.dart';
import '../servicos/servicos.dart';
import '../widgets/comum.dart';
import 'login_tela.dart';

class PedidosTela extends StatefulWidget {
  const PedidosTela({super.key});

  @override
  State<PedidosTela> createState() => _PedidosTelaState();
}

class _PedidosTelaState extends State<PedidosTela> {
  List<Pedido>? _lista;
  String? _erro;

  @override
  void initState() {
    super.initState();
    sessao.addListener(_carregar);
    _carregar();
  }

  @override
  void dispose() {
    sessao.removeListener(_carregar);
    super.dispose();
  }

  Future<void> _carregar() async {
    if (!sessao.logado) {
      if (mounted) setState(() => _lista = null);
      return;
    }
    try {
      final l = await pedidos.meus();
      if (mounted) setState(() { _lista = l; _erro = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    }
  }

  Future<void> _cancelar(Pedido p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Cancelar pedido #${p.id}?'),
        content: const Text('As peças voltam para o estoque e o valor é estornado.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Manter')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cancelar pedido')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await pedidos.cancelar(p.id);
      if (mounted) mostrarMensagem(context, 'Pedido cancelado.');
      _carregar();
    } on ApiException catch (e) {
      if (mounted) mostrarMensagem(context, e.mensagem, erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget corpo;
    if (!sessao.logado) {
      corpo = EstadoVazio(
        icone: Icons.lock_outline,
        mensagem: 'Entre na sua conta para ver seus pedidos.',
        acao: FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginTela())),
          child: const Text('ENTRAR'),
        ),
      );
    } else if (_erro != null) {
      corpo = EstadoVazio(icone: Icons.wifi_off, mensagem: _erro!,
          acao: OutlinedButton(onPressed: _carregar, child: const Text('Tentar de novo')));
    } else if (_lista == null) {
      corpo = const Center(child: CircularProgressIndicator(color: Cores.amarelo));
    } else if (_lista!.isEmpty) {
      corpo = const EstadoVazio(icone: Icons.inventory_2_outlined, mensagem: 'Você ainda não fez pedidos.');
    } else {
      corpo = RefreshIndicator(
        color: Cores.amarelo,
        onRefresh: _carregar,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _lista!.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _CardPedido(pedido: _lista![i], onCancelar: _cancelar),
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('Meus pedidos')), body: corpo);
  }
}

class _CardPedido extends StatelessWidget {
  final Pedido pedido;
  final void Function(Pedido) onCancelar;
  const _CardPedido({required this.pedido, required this.onCancelar});

  Color get _corStatus => switch (pedido.status) {
        'Entregue' => Cores.sucesso,
        'Cancelado' => Cores.erro,
        'Enviado' => const Color(0xFF93C5FD),
        'Em Separação' => const Color(0xFFFFB547),
        _ => Cores.amarelo,
      };

  @override
  Widget build(BuildContext context) {
    final p = pedido;
    return Card(
      color: Cores.superficie,
      elevation: 0,
      shape: formaCard,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Pedido #${p.id}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _corStatus.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(99)),
              child: Text(p.status, style: TextStyle(color: _corStatus, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ]),
          Text('${dataHora(p.data)} · ${p.formaPagamento}${p.parcelas > 1 ? ' ${p.parcelas}x' : ''} · via ${p.origem}',
              style: const TextStyle(color: Cores.textoSuave, fontSize: 12)),
          const SizedBox(height: 12),
          if (!p.cancelado)
            Row(children: [
              for (var i = 0; i < Pedido.etapas.length; i++) ...[
                Expanded(
                  child: Column(children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: i <= p.etapaAtual ? Cores.amarelo : Cores.superficie2,
                      child: Icon(i <= p.etapaAtual ? Icons.check : Icons.circle_outlined,
                          size: 14, color: i <= p.etapaAtual ? Colors.black : Cores.textoSuave),
                    ),
                    const SizedBox(height: 4),
                    Text(Pedido.etapas[i], textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10, color: i <= p.etapaAtual ? Colors.white : Cores.textoSuave)),
                  ]),
                ),
              ],
            ]),
          const Divider(height: 24),
          for (final item in p.itens)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(width: 44, height: 44, child: ImagemProduto(item.img))),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${item.qtd}× ${item.nome} (${item.tamanho})',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                ),
                Text(brl(item.preco * item.qtd), style: const TextStyle(fontSize: 13)),
              ]),
            ),
          const Divider(height: 16),
          Row(children: [
            if (p.codigoRastreio != null)
              Expanded(child: Text('Rastreio: ${p.codigoRastreio}', style: const TextStyle(color: Cores.textoSuave, fontSize: 12)))
            else
              const Spacer(),
            Text(brl(p.total), style: const TextStyle(color: Cores.amarelo, fontWeight: FontWeight.w900, fontSize: 18)),
          ]),
          if (p.podeCancelar)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => onCancelar(p),
                style: TextButton.styleFrom(foregroundColor: Cores.erro),
                child: const Text('Cancelar pedido'),
              ),
            ),
        ]),
      ),
    );
  }
}
