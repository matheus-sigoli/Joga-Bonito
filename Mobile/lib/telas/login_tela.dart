// ============================================================================
// LOGIN / CADASTRO — autenticação JWT na API. Retorna true ao entrar.
// ============================================================================
import 'package:flutter/material.dart';

import '../servicos/api_cliente.dart';
import '../servicos/servicos.dart';
import '../widgets/comum.dart';

class LoginTela extends StatefulWidget {
  const LoginTela({super.key});

  @override
  State<LoginTela> createState() => _LoginTelaState();
}

class _LoginTelaState extends State<LoginTela> {
  final _form = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _cadastro = false;
  bool _aceite = false;
  bool _ocultar = true;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _nome.dispose();
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_form.currentState!.validate()) return;
    if (_cadastro && !_aceite) {
      setState(() => _erro = 'Aceite a Política de Privacidade para continuar.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      if (_cadastro) {
        await sessao.cadastrar(_nome.text, _email.text, _senha.text);
      } else {
        await sessao.entrar(_email.text, _senha.text);
      }
      if (!mounted) return;
      mostrarMensagem(context, 'Bem-vindo, ${sessao.usuario!.primeiroNome}! ⚽');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_cadastro ? 'Criar conta' : 'Entrar')),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Center(child: Image.asset('assets/escudo.png', height: 96, excludeFromSemantics: true)),
            const SizedBox(height: 20),
            if (_cadastro)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: _nome,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(labelText: 'Nome completo'),
                  validator: (v) => (v ?? '').trim().split(' ').where((s) => s.isNotEmpty).length >= 2
                      ? null
                      : 'Informe nome e sobrenome',
                ),
              ),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'E-mail'),
              validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'E-mail inválido',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _senha,
              obscureText: _ocultar,
              autofillHints: [_cadastro ? AutofillHints.newPassword : AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Senha',
                helperText: _cadastro ? 'Mínimo 8 caracteres, com letras e números' : null,
                suffixIcon: IconButton(
                  tooltip: _ocultar ? 'Mostrar senha' : 'Ocultar senha',
                  icon: Icon(_ocultar ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _ocultar = !_ocultar),
                ),
              ),
              validator: (v) {
                final s = v ?? '';
                if (!_cadastro) return s.isEmpty ? 'Informe a senha' : null;
                return s.length >= 8 && RegExp(r'[A-Za-z]').hasMatch(s) && RegExp(r'\d').hasMatch(s)
                    ? null
                    : 'Use 8+ caracteres com letras e números';
              },
            ),
            if (_cadastro)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _aceite,
                onChanged: (v) => setState(() => _aceite = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Li e aceito a Política de Privacidade (LGPD).', style: TextStyle(fontSize: 13)),
              ),
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_erro!, style: const TextStyle(color: Cores.erro)),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _enviando ? null : _enviar,
              child: _enviando
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(_cadastro ? 'CRIAR CONTA' : 'ENTRAR'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _cadastro = !_cadastro;
                _erro = null;
              }),
              child: Text(_cadastro ? 'Já tenho conta' : 'Criar uma conta'),
            ),
            if (!_cadastro)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Demonstração: matheus@estudante.com / Cliente@2026',
                    textAlign: TextAlign.center, style: TextStyle(color: Cores.textoSuave, fontSize: 12)),
              ),
          ]),
        ),
      );
}
