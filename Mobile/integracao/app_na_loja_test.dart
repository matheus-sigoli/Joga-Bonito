// ============================================================================
// APP NA LOJA DE VERDADE — o código do aplicativo (ApiCliente, serviços e modelos)
// contra a API .NET e o SQL Server reais, no job de integração do pipeline.
//
// Cobre o roteiro manual 5 (celular ligado à loja do PC) no que não depende da tela:
// achar a loja, cadastro e login por token, catálogo e modo offline, CEP, compra com
// origem Mobile (inclusive reenvio com a mesma chave), avaliação, Meus dados (LGPD),
// cancelamento pelo SITE devolvendo o estoque, Vendas por canal no painel e exclusão
// da conta. As telas têm seus próprios testes em test/.
//
// Rodar:  JB_API=http://localhost:5000 flutter test integracao/
// ============================================================================
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jogabonito_mobile/modelos/modelos.dart';
import 'package:jogabonito_mobile/servicos/api_cliente.dart';
import 'package:jogabonito_mobile/servicos/cofre.dart';
import 'package:jogabonito_mobile/servicos/descoberta.dart';
import 'package:jogabonito_mobile/servicos/servicos.dart';
import 'package:shared_preferences/shared_preferences.dart';

final base = Platform.environment['JB_API'] ?? 'http://localhost:5000';
const senha = 'Chuteira#Azul2026';
final email = 'app.${DateTime.now().millisecondsSinceEpoch}@teste.com';

/// Painel admin pela API (token), sem mexer na sessão do app.
Future<Map<String, dynamic>> painel() async {
  final login = await http.post(Uri.parse('$base/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': 'admin@jogabonito.com', 'senha': 'Admin@2026'}));
  expect(login.statusCode, 200, reason: login.body);
  final token = (jsonDecode(login.body) as Map)['token'] as String;
  final r = await http.get(Uri.parse('$base/api/admin/dashboard'), headers: {'Authorization': 'Bearer $token'});
  expect(r.statusCode, 200, reason: r.body);
  return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
}

int pedidosDoApp(Map<String, dynamic> dash) {
  final canais = (dash['vendasPorCanal'] as List).cast<Map<String, dynamic>>();
  return (canais.firstWhere((c) => c['canal'] == 'Mobile', orElse: () => {'pedidos': 0})['pedidos'] as num).toInt();
}

int saldo(ProdutoDetalhe d, String tamanho) => d.tamanhos.firstWhere((t) => t.tamanho == tamanho).quantidade;

void main() {
  late SessaoServico sessao;
  late CofreMemoria cofre;
  late Produto produto;
  late String tamanho;
  late int estoqueAntes;
  late int pedidoId;
  late int mobileAntes;
  late int totalCatalogo;

  setUpAll(() async {
    // Pasta integracao/ (fora de test/, para não rodar no job sem API): o analisador não a vê como teste.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    cofre = CofreMemoria();
    sessao = SessaoServico(cofre: cofre);
  });

  test('acha a loja: /api/loja responde Joga Bonito e o app aceita o endereço', () async {
    expect(await DescobertaLoja.ehLoja(base, limite: const Duration(seconds: 5)), isTrue);
    expect(await DescobertaLoja.ehLoja('http://127.0.0.1:9'), isFalse, reason: 'porta fechada não é a loja');
    await api.alterarServidor(base);
    expect(api.baseUrl, base);
  });

  test('catálogo: os 36 produtos com foto, salvos para o modo offline', () async {
    final (lista, doCache) = await catalogo.listar();
    expect(doCache, isFalse);
    expect(lista.length, greaterThanOrEqualTo(36));
    expect(lista.where((p) => p.img.isNotEmpty).length, lista.length);
    totalCatalogo = lista.length;
    expect(catalogo.sincronizado.value, isNotNull, reason: 'Perfil mostra a data da sincronização');

    // um produto com estoque para a compra
    for (final p in lista) {
      final d = await catalogo.detalhe(p.id);
      final t = d.tamanhos.where((t) => t.quantidade >= 3).firstOrNull;
      if (t != null) {
        produto = p;
        tamanho = t.tamanho;
        estoqueAntes = t.quantidade;
        break;
      }
    }
  });

  test('cadastro e login pelo app: token só no cofre, nunca no shared_preferences', () async {
    await sessao.cadastrar('Teste do App', email, senha);
    expect(sessao.logado, isTrue);
    expect(sessao.usuario!.email, email);
    expect(await cofre.ler(), isNotNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().any((k) => (prefs.get(k)?.toString() ?? '').contains(api.token!)), isFalse);
  });

  test('CEP 01310-100 preenche o endereço pelo ViaCEP', () async {
    final e = await cep.buscar('01310-100');
    if (e == null) {
      markTestSkipped('ViaCEP fora do ar agora (o app deixa digitar à mão)');
      return;
    }
    expect(e.rua, contains('Paulista'));
    expect(e.cidade, 'São Paulo');
    expect(e.uf, 'SP');
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('compra pelo app: origem Mobile, reenvio com a mesma chave não duplica, painel conta o canal', () async {
    mobileAntes = pedidosDoApp(await painel());
    final itens = [
      {'produtoId': produto.id, 'tamanho': tamanho, 'quantidade': 2}
    ];
    final resumo = await pedidos.simular(itens, null);
    expect(resumo.total, greaterThan(0));

    final chave = PedidoServico.novaChave();
    final endereco = {
      'cep': '01310100', 'rua': 'Avenida Paulista', 'numero': '1000', 'complemento': null,
      'bairro': 'Bela Vista', 'cidade': 'São Paulo', 'estado': 'SP',
    };
    final a = await pedidos.criar(itens: itens, formaPagamento: 'PIX', parcelas: 1, endereco: endereco, chaveIdempotencia: chave);
    final b = await pedidos.criar(itens: itens, formaPagamento: 'PIX', parcelas: 1, endereco: endereco, chaveIdempotencia: chave);
    pedidoId = (a['pedidoId'] as num).toInt();
    expect((b['pedidoId'] as num).toInt(), pedidoId, reason: 'mesma tentativa de compra = mesmo pedido');
    expect((a['total'] as num).toDouble(), closeTo(resumo.total, 0.01));

    final depois = await catalogo.detalhe(produto.id);
    expect(saldo(depois, tamanho), estoqueAntes - 2, reason: 'estoque baixou uma vez só');

    final meus = await pedidos.meus();
    final p = meus.firstWhere((x) => x.id == pedidoId);
    expect(p.origem, 'Mobile');
    expect(p.status, 'Pago');
    expect(meus.where((x) => x.id == pedidoId).length, 1);

    expect(pedidosDoApp(await painel()), mobileAntes + 1, reason: 'Vendas por canal: App (celular)');
  });

  test('avaliação pelo app aparece para todos (mesma regra do site)', () async {
    final msg = await avaliacoes.enviar(produto.id, 5, 'Comprei pelo app, chegou certinho.');
    expect(msg, isNotEmpty);
    final lista = await avaliacoes.listar(produto.id);
    expect(lista.any((a) => a.comentario == 'Comprei pelo app, chegou certinho.' && a.nota == 5), isTrue);
  });

  test('Meus dados (LGPD) mostra a conta, o pedido e a avaliação', () async {
    final dados = jsonEncode(await sessao.meusDados());
    expect(dados, contains(email));
    expect(dados, contains('$pedidoId'));
    expect(dados, contains('Comprei pelo app'));
  });

  test('cancelado pelo SITE (cookie de sessão): o app vê Cancelado e o estoque volta', () async {
    final cliente = http.Client();
    try {
      final login = await cliente.post(Uri.parse('$base/api/auth/login'),
          headers: {'Content-Type': 'application/json', 'X-JB-Cliente': 'web'},
          body: jsonEncode({'email': email, 'senha': senha}));
      expect(login.statusCode, 200, reason: login.body);
      final cookie = login.headers['set-cookie']!.split(';').first; // jb_sessao=...
      expect(cookie, startsWith('jb_sessao='));
      final r = await cliente.post(Uri.parse('$base/api/pedidos/$pedidoId/cancelar'),
          headers: {'Cookie': cookie, 'X-JB-Requisicao': '1'});
      expect(r.statusCode, 204, reason: r.body);
    } finally {
      cliente.close();
    }
    final p = (await pedidos.meus()).firstWhere((x) => x.id == pedidoId);
    expect(p.status, 'Cancelado');
    expect(saldo(await catalogo.detalhe(produto.id), tamanho), estoqueAntes);
    expect(pedidosDoApp(await painel()), mobileAntes, reason: 'pedido cancelado sai de Vendas por canal');
  });

  test('sem conexão: o app mostra o catálogo salvo em vez de travar', () async {
    api.baseUrl = 'http://127.0.0.1:9';
    try {
      final (lista, doCache) = await catalogo.listar();
      expect(doCache, isTrue);
      expect(lista.length, totalCatalogo);
    } finally {
      api.baseUrl = base;
    }
  });

  test('excluir a conta pelo app (LGPD): sai da sessão e o login deixa de valer', () async {
    await sessao.excluirConta(senha);
    expect(sessao.logado, isFalse);
    expect(await cofre.ler(), isNull);
    expect(() => sessao.entrar(email, senha), throwsA(isA<ApiException>()));
  });
}
