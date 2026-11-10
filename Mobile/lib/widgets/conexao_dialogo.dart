// ============================================================================
// "Conectar à loja" — usado em Perfil › Servidor da API e na tela de "sem conexão".
// Procura o PC na rede Wi-Fi sozinho ou aceita o endereço digitado, e só salva
// depois de confirmar que ali está a API da Joga Bonito (GET /api/loja).
// ============================================================================
import 'package:flutter/material.dart';

import '../servicos/api_cliente.dart';
import '../servicos/descoberta.dart';
import 'comum.dart';

/// Abre a janela de conexão. Devolve true se o app ficou conectado a uma loja.
Future<bool> conectarLoja(BuildContext context) async {
  final conectado = await showDialog<bool>(
    context: context,
    builder: (_) => const _ConexaoDialogo(),
  );
  return conectado ?? false;
}

class _ConexaoDialogo extends StatefulWidget {
  const _ConexaoDialogo();

  @override
  State<_ConexaoDialogo> createState() => _ConexaoDialogoState();
}

class _ConexaoDialogoState extends State<_ConexaoDialogo> {
  final _ctrl = TextEditingController(text: ApiCliente.instancia.baseUrl);
  bool _procurando = false;
  bool _testando = false;
  double? _progresso;
  String? _mensagem;
  bool _mensagemErro = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _procurar() async {
    setState(() {
      _procurando = true;
      _progresso = 0;
      _mensagem = 'Procurando a loja na sua rede Wi-Fi...';
      _mensagemErro = false;
    });
    final achado = await DescobertaLoja.procurar(
      progresso: (feitos, total) {
        if (mounted) setState(() => _progresso = feitos / total);
      },
    );
    if (!mounted) return;
    setState(() => _procurando = false);
    if (achado == null) {
      setState(() {
        _mensagem = 'Não achei a loja nesta rede. Confira se o PC rodou o iniciar-com-celular.bat '
            'e se o celular está no mesmo Wi-Fi. Você também pode digitar o endereço que aparece na janela do PC.';
        _mensagemErro = true;
      });
      return;
    }
    _ctrl.text = achado;
    await _salvar();
  }

  Future<void> _salvar() async {
    setState(() {
      _testando = true;
      _mensagem = null;
    });
    final api = ApiCliente.instancia;
    final anterior = api.baseUrl;
    try {
      final limpo = ApiCliente.normalizarServidor(_ctrl.text);
      if (!await DescobertaLoja.ehLoja(limpo, limite: const Duration(seconds: 5))) {
        throw ApiException('Nenhuma loja Joga Bonito respondeu em $limpo.', 0);
      }
      await api.alterarServidor(limpo);
      if (!mounted) return;
      mostrarMensagem(context, 'Conectado à loja em ${api.baseUrl}');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      api.baseUrl = anterior;
      if (mounted) {
        setState(() {
          _mensagem = e.mensagem;
          _mensagemErro = true;
        });
      }
    } finally {
      if (mounted) setState(() => _testando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ocupado = _procurando || _testando;
    return AlertDialog(
      title: const Text('Conectar à loja'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('No PC, rode iniciar-com-celular.bat. Com o celular no mesmo Wi-Fi, toque em Procurar.',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: ocupado ? null : _procurar,
            icon: const Icon(Icons.wifi_find),
            label: const Text('PROCURAR A LOJA NA REDE'),
          ),
          if (_procurando) ...[
            const SizedBox(height: 10),
            Semantics(
              label: 'Procurando a loja',
              value: '${((_progresso ?? 0) * 100).round()}%',
              child: LinearProgressIndicator(value: _progresso, color: Cores.amarelo),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            enabled: !ocupado,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Ou digite o endereço', hintText: 'http://192.168.0.10:5000'),
            onSubmitted: (_) => _salvar(),
          ),
          const SizedBox(height: 6),
          const Text('Emulador: http://10.0.2.2:5000 · Publicada: https://... (fora da rede local só HTTPS)',
              style: TextStyle(fontSize: 11, color: Cores.textoSuave)),
          if (_mensagem != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(_mensagem!,
                  style: TextStyle(fontSize: 13, color: _mensagemErro ? Cores.erro : Cores.textoSuave)),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: ocupado ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
        TextButton(
          onPressed: ocupado ? null : _salvar,
          child: _testando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Salvar'),
        ),
      ],
    );
  }
}
