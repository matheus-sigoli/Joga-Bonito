// ============================================================================
// PERFIL — conta, sincronização e configuração do servidor da API.
// ============================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../servicos/api_cliente.dart';
import '../servicos/servicos.dart';
import '../widgets/comum.dart';
import '../widgets/conexao_dialogo.dart';
import 'login_tela.dart';

class PerfilTela extends StatefulWidget {
  const PerfilTela({super.key});

  @override
  State<PerfilTela> createState() => _PerfilTelaState();
}

class _PerfilTelaState extends State<PerfilTela> {
  DateTime? _sincronizado;

  @override
  void initState() {
    super.initState();
    catalogo.ultimaSincronizacao().then((d) {
      if (mounted) setState(() => _sincronizado = d);
    });
  }

  Future<void> _configurarServidor() async {
    if (await conectarLoja(context)) {
      // Novo servidor: o catálogo offline antigo é de outra loja/versão
      final d = await catalogo.ultimaSincronizacao();
      if (mounted) setState(() => _sincronizado = d);
    }
    if (mounted) setState(() {});
  }

  /// LGPD (art. 18): mostra o que a loja guarda desta conta e permite copiar o JSON completo.
  Future<void> _meusDados() async {
    Map<String, dynamic> dados;
    try {
      dados = await sessao.meusDados();
    } on ApiException catch (e) {
      if (mounted) mostrarMensagem(context, e.mensagem, erro: true);
      return;
    }
    if (!mounted) return;
    final conta = (dados['conta'] as Map?) ?? const {};
    int qtd(String chave) => (dados[chave] as List?)?.length ?? 0;
    final json = const JsonEncoder.withIndent('  ').convert(dados);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Meus dados (LGPD)'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Nome: ${conta['nome'] ?? '-'}'),
            Text('E-mail: ${conta['email'] ?? '-'}'),
            const SizedBox(height: 8),
            Text('Endereços: ${qtd('enderecos')} · Pedidos: ${qtd('pedidos')} · Avaliações: ${qtd('avaliacoes')}'),
            Text('Registros de acesso: ${qtd('acessos')}'),
            const SizedBox(height: 10),
            Text(dados['observacao'] as String? ?? '', style: const TextStyle(fontSize: 12, color: Cores.textoSuave)),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (c.mounted) Navigator.pop(c);
              if (mounted) mostrarMensagem(context, 'Dados copiados (JSON). Cole num e-mail ou arquivo para guardar.');
            },
            child: const Text('Copiar tudo (JSON)'),
          ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fechar')),
        ],
      ),
    );
  }

  Future<void> _trocarSenha() async {
    final atual = TextEditingController(), nova = TextEditingController(), confirma = TextEditingController();
    final chave = GlobalKey<FormState>();
    final salvar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Trocar senha'),
        content: Form(
          key: chave,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: atual,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Senha atual'),
              validator: (v) => (v ?? '').isEmpty ? 'Informe a senha atual' : null,
            ),
            TextFormField(
              controller: nova,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'Nova senha', helperText: '8 a 64 caracteres, letras e números'),
              validator: (v) {
                final s = v ?? '';
                final forte = s.length >= 8 && s.length <= 64 && s.contains(RegExp(r'[A-Za-z]')) && s.contains(RegExp(r'\d'));
                return forte ? null : 'Use de 8 a 64 caracteres, com letras e números';
              },
            ),
            TextFormField(
              controller: confirma,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirme a nova senha'),
              validator: (v) => v == nova.text ? null : 'A confirmação não confere',
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () { if (chave.currentState!.validate()) Navigator.pop(c, true); },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (salvar == true) {
      try {
        await sessao.trocarSenha(atual.text, nova.text);
        if (mounted) mostrarMensagem(context, 'Senha alterada.');
      } on ApiException catch (e) {
        if (mounted) mostrarMensagem(context, e.mensagem, erro: true);
      }
    }
    atual.dispose();
    nova.dispose();
    confirma.dispose();
  }

  Future<void> _excluirConta() async {
    final senha = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Excluir minha conta'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Apaga nome, e-mail, endereços e avaliações. Os pedidos ficam guardados sem dados pessoais '
              '(obrigação fiscal). Não dá para desfazer. Para guardar uma cópia antes, use Perfil › Meus dados.',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: senha,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Confirme sua senha'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Excluir', style: TextStyle(color: Cores.erro)),
          ),
        ],
      ),
    );
    if (confirmar == true) {
      try {
        await sessao.excluirConta(senha.text);
        await carrinho.limpar();
        if (mounted) mostrarMensagem(context, 'Conta excluída. Seus dados pessoais foram removidos.');
      } on ApiException catch (e) {
        if (mounted) mostrarMensagem(context, e.mensagem, erro: true);
      }
    }
    senha.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Perfil')),
        body: ListenableBuilder(
          listenable: sessao,
          builder: (context, _) {
            final u = sessao.usuario;
            return ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                color: Cores.superficie,
                elevation: 0,
                shape: formaCard,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: u == null
                      ? Column(children: [
                          const Text('Entre para comprar, acompanhar pedidos e usar cupons.', textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginTela())),
                            child: const Text('ENTRAR OU CRIAR CONTA'),
                          ),
                        ])
                      : Row(children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: Cores.verde,
                            child: Text(u.nome.split(' ').where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join().toUpperCase(),
                                style: const TextStyle(color: Cores.amarelo, fontWeight: FontWeight.w900)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(u.nome, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                              Text(u.email, style: const TextStyle(color: Cores.textoSuave)),
                              Text(u.ehAdmin ? 'Administrador' : 'Cliente',
                                  style: const TextStyle(color: Cores.amarelo, fontSize: 12)),
                            ]),
                          ),
                        ]),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.wifi_find),
                title: const Text('Conectar à loja'),
                subtitle: Text('${api.baseUrl}\nProcurar o PC na rede Wi-Fi ou digitar o endereço'),
                isThreeLine: true,
                onTap: _configurarServidor,
              ),
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Catálogo offline'),
                subtitle: Text(_sincronizado == null
                    ? 'Ainda não sincronizado'
                    : 'Última sincronização: ${dataHora(_sincronizado!)}'),
              ),
              const ListTile(
                leading: Icon(Icons.accessibility_new),
                title: Text('Acessibilidade'),
                subtitle: Text('O app respeita o tamanho de fonte e o leitor de tela (TalkBack/VoiceOver) do aparelho.'),
              ),
              if (u != null)
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Meus dados (LGPD)'),
                  subtitle: const Text('Veja e copie tudo o que a loja guarda da sua conta'),
                  onTap: _meusDados,
                ),
              if (u != null)
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Trocar senha'),
                  subtitle: const Text('Exige a senha atual'),
                  onTap: _trocarSenha,
                ),
              if (u != null)
                ListTile(
                  leading: const Icon(Icons.devices_other),
                  title: const Text('Sair de todos os aparelhos'),
                  subtitle: const Text('Encerra a conta no site e em outros celulares'),
                  onTap: () async {
                    try {
                      await sessao.sairDeTodos();
                    } on ApiException catch (e) {
                      if (context.mounted) mostrarMensagem(context, e.mensagem, erro: true);
                    }
                  },
                ),
              if (u != null)
                ListTile(
                  leading: const Icon(Icons.person_off_outlined),
                  title: const Text('Excluir minha conta (LGPD)'),
                  subtitle: const Text('Remove seus dados pessoais'),
                  onTap: _excluirConta,
                ),
              if (u != null)
                ListTile(
                  leading: const Icon(Icons.logout, color: Cores.erro),
                  title: const Text('Sair da conta', style: TextStyle(color: Cores.erro)),
                  onTap: () => sessao.sair(),
                ),
              const SizedBox(height: 24),
              const Text('Joga Bonito · PIM IV · UNIP 2026/2',
                  textAlign: TextAlign.center, style: TextStyle(color: Cores.textoSuave, fontSize: 12)),
            ]);
          },
        ),
      );
}
