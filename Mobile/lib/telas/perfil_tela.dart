// ============================================================================
// PERFIL — conta, sincronização e configuração do servidor da API.
// ============================================================================
import 'package:flutter/material.dart';

import '../servicos/api_cliente.dart';
import '../servicos/servicos.dart';
import '../widgets/comum.dart';
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
    final ctrl = TextEditingController(text: api.baseUrl);
    final novo = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Servidor da API'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: ctrl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Endereço')),
          const SizedBox(height: 10),
          const Text('Emulador Android: http://10.0.2.2:5000\nCelular: http://IP-DO-PC:5000 (mesma rede Wi-Fi)\nPublicado: https://... (HTTPS obrigatório fora da rede local)',
              style: TextStyle(fontSize: 12, color: Cores.textoSuave)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Salvar')),
        ],
      ),
    );
    ctrl.dispose();
    if (novo == null || novo.trim().isEmpty) return;
    try {
      await api.alterarServidor(novo);
      await api.get('/health/ready');
      if (mounted) mostrarMensagem(context, 'Conectado a ${api.baseUrl}');
    } on ApiException catch (e) {
      if (mounted) mostrarMensagem(context, e.mensagem, erro: true);
    }
    if (mounted) setState(() {});
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
              '(obrigação fiscal). Não dá para desfazer. Para baixar seus dados antes, use o site: Meus pedidos › Meus dados.',
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
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Servidor da API'),
                subtitle: Text(api.baseUrl),
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
