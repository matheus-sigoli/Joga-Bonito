// ============================================================================
// Serviços do app: sessão (JWT), carrinho, catálogo com cache offline e pedidos.
// Sessão e carrinho são ChangeNotifier: as telas se atualizam sozinhas.
// ============================================================================
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../modelos/modelos.dart';
import 'api_cliente.dart';
import 'cofre.dart';

final api = ApiCliente.instancia;

// ----------------------------------------------------------------------------
// SESSÃO
// ----------------------------------------------------------------------------
class SessaoServico extends ChangeNotifier {
  static const _chaveTokenAntigo = 'jb_token'; // versões antigas guardavam o token aqui
  static const _chaveUsuario = 'jb_usuario';
  static const _chaveExpira = 'jb_expira';

  /// Token no armazenamento seguro; nome e perfil (não secretos) no shared_preferences.
  final CofreToken cofre;

  Usuario? usuario;
  bool get logado =>
      usuario != null && api.token != null && (api.tokenExpiraEm?.isAfter(DateTime.now()) ?? false);

  SessaoServico({CofreToken? cofre}) : cofre = cofre ?? CofreSeguro() {
    api.aoExpirarSessao = () => sair();
  }

  Future<void> restaurar() async {
    final prefs = await SharedPreferences.getInstance();

    // Migração: token salvo em texto comum por versões antigas vai para o cofre e some do arquivo
    final antigo = prefs.getString(_chaveTokenAntigo);
    if (antigo != null) {
      await cofre.gravar(antigo);
      await prefs.remove(_chaveTokenAntigo);
    }

    final expira = DateTime.tryParse(prefs.getString(_chaveExpira) ?? '');
    final json = prefs.getString(_chaveUsuario);
    final token = await cofre.ler();
    if (json != null && token != null && expira != null && expira.isAfter(DateTime.now())) {
      usuario = Usuario.fromJson(jsonDecode(json) as Map<String, dynamic>);
      api.token = token;
      api.tokenExpiraEm = expira;
    } else {
      await sair();
    }
    notifyListeners();
  }

  Future<void> entrar(String email, String senha) async {
    final r = await api.post('/api/auth/login', {'email': email.trim(), 'senha': senha}) as Map<String, dynamic>;
    await _guardar(r);
  }

  Future<void> _guardar(Map<String, dynamic> r) async {
    usuario = Usuario.fromJson(r['usuario'] as Map<String, dynamic>);
    api.token = r['token'] as String;
    api.tokenExpiraEm = DateTime.tryParse(r['expiraEm'] as String? ?? '')?.toLocal();
    await cofre.gravar(api.token!);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chaveUsuario, jsonEncode(usuario!.toJson()));
    await prefs.setString(_chaveExpira, r['expiraEm'] as String);
    notifyListeners();
  }

  Future<void> cadastrar(String nome, String email, String senha) async {
    await api.post('/api/auth/cadastro', {'nome': nome.trim(), 'email': email.trim(), 'senha': senha, 'aceiteLgpd': true});
    await entrar(email, senha);
  }

  /// POST /api/auth/trocar-senha — exige a senha atual; a API encerra as outras sessões
  /// e devolve um token novo para este aparelho continuar logado.
  Future<void> trocarSenha(String atual, String nova) async {
    final r = await api.post('/api/auth/trocar-senha', {'senhaAtual': atual, 'novaSenha': nova}) as Map<String, dynamic>;
    await _guardar(r);
  }

  /// POST /api/auth/excluir-conta — LGPD: anonimiza os dados pessoais (exige a senha).
  Future<void> excluirConta(String senha) async {
    await api.post('/api/auth/excluir-conta', {'senha': senha});
    await sair();
  }

  /// GET /api/auth/meus-dados — LGPD: tudo o que a loja guarda desta conta (JSON).
  Future<Map<String, dynamic>> meusDados() async =>
      await api.get('/api/auth/meus-dados') as Map<String, dynamic>;

  /// POST /api/auth/sair-de-todos — invalida o token em todos os aparelhos.
  Future<void> sairDeTodos() async {
    await api.post('/api/auth/sair-de-todos');
    await sair();
  }

  Future<void> sair() async {
    usuario = null;
    api.token = null;
    api.tokenExpiraEm = null;
    await cofre.apagar();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chaveTokenAntigo);
    await prefs.remove(_chaveUsuario);
    await prefs.remove(_chaveExpira);
    notifyListeners();
  }
}

// ----------------------------------------------------------------------------
// CARRINHO (persistido no aparelho)
// ----------------------------------------------------------------------------
class CarrinhoServico extends ChangeNotifier {
  static const _chave = 'jb_carrinho';
  static const limiteFreteGratis = 299.0;
  static const valorFrete = 19.90;

  final List<ItemCarrinho> itens = [];

  int get quantidade => itens.fold(0, (s, i) => s + i.quantidade);
  double get subtotal => itens.fold(0.0, (s, i) => s + i.subtotal);
  double get freteEstimado => subtotal == 0 || subtotal >= limiteFreteGratis ? 0 : valorFrete;

  Future<void> carregar() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_chave);
    if (json != null) {
      itens
        ..clear()
        ..addAll((jsonDecode(json) as List).map((e) => ItemCarrinho.fromJson(e as Map<String, dynamic>)));
    }
    notifyListeners();
  }

  Future<void> _salvar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chave, jsonEncode(itens.map((i) => i.toJson()).toList()));
    notifyListeners();
  }

  Future<void> adicionar(Produto p, String tamanho, int qtd) {
    final existente = itens.where((i) => i.produtoId == p.id && i.tamanho == tamanho).firstOrNull;
    if (existente != null) {
      existente.quantidade = (existente.quantidade + qtd).clamp(1, 10);
    } else {
      itens.add(ItemCarrinho(
          produtoId: p.id, nome: p.nome, img: p.img, preco: p.precoFinal, tamanho: tamanho, quantidade: qtd));
    }
    return _salvar();
  }

  Future<void> alterar(ItemCarrinho item, int novaQtd) {
    if (novaQtd <= 0) {
      itens.remove(item);
    } else {
      item.quantidade = novaQtd.clamp(1, 10);
    }
    return _salvar();
  }

  Future<void> limpar() {
    itens.clear();
    return _salvar();
  }

  List<Map<String, dynamic>> paraApi() => itens.map((i) => i.paraApi()).toList();
}

// ----------------------------------------------------------------------------
// CATÁLOGO — sincronização: a última lista válida fica em cache no aparelho e
// é exibida quando não há conexão com a API.
// ----------------------------------------------------------------------------
class CatalogoServico {
  static const _chaveCache = 'jb_cache_produtos';
  static const _chaveCacheData = 'jb_cache_data';

  /// Retorna (produtos, veioDoCache).
  Future<(List<Produto>, bool)> listar({String? categoria, String? linha, String? busca, String ordem = 'relevancia'}) async {
    final params = <String, String>{
      if (categoria != null && categoria.isNotEmpty) 'categoria': categoria,
      if (linha != null && linha.isNotEmpty) 'linha': linha,
      if (busca != null && busca.isNotEmpty) 'busca': busca,
      'ordem': ordem,
    };
    final qs = Uri(queryParameters: params).query;
    try {
      final dados = await api.get('/api/produtos?$qs') as List;
      final produtos = dados.map((e) => Produto.fromJson(e as Map<String, dynamic>)).toList();
      if (params.length == 1) await _salvarCache(dados); // lista completa sem filtros
      return (produtos, false);
    } on ApiException catch (e) {
      if (!e.semConexao) rethrow;
      final cache = await _lerCache();
      if (cache.isEmpty) rethrow;
      final filtrados = cache
          .where((p) => categoria == null || categoria.isEmpty || p.categoriaSlug == categoria)
          .where((p) => linha == null || linha.isEmpty || p.linha == linha)
          .where((p) => busca == null || busca.isEmpty || p.nome.toLowerCase().contains(busca.toLowerCase()))
          .toList();
      return (filtrados, true);
    }
  }

  Future<ProdutoDetalhe> detalhe(int id) async =>
      ProdutoDetalhe.fromJson(await api.get('/api/produtos/$id') as Map<String, dynamic>);

  Future<DateTime?> ultimaSincronizacao() async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString(_chaveCacheData) ?? '');
  }

  Future<void> _salvarCache(List dados) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chaveCache, jsonEncode(dados));
    await prefs.setString(_chaveCacheData, DateTime.now().toIso8601String());
  }

  Future<List<Produto>> _lerCache() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_chaveCache);
    if (json == null) return [];
    return (jsonDecode(json) as List).map((e) => Produto.fromJson(e as Map<String, dynamic>)).toList();
  }
}

// ----------------------------------------------------------------------------
// PEDIDOS
// ----------------------------------------------------------------------------
class PedidoServico {
  Future<ResumoPedido> simular(List<Map<String, dynamic>> itens, String? cupom) async =>
      ResumoPedido.fromJson(await api.post('/api/pedidos/simular', {'itens': itens, 'cupom': cupom})
          as Map<String, dynamic>);

  Future<Map<String, dynamic>> criar({
    required List<Map<String, dynamic>> itens,
    required String formaPagamento,
    required int parcelas,
    String? cupom,
    required Map<String, dynamic> endereco,
    String? chaveIdempotencia,
  }) async =>
      await api.post('/api/pedidos', {
        'itens': itens,
        'formaPagamento': formaPagamento,
        'parcelas': parcelas,
        'cupom': cupom,
        'endereco': endereco,
        'origem': 'Mobile',
      }, {
        if (chaveIdempotencia != null) 'Idempotency-Key': chaveIdempotencia,
      }, const Duration(seconds: 30)) as Map<String, dynamic>;

  /// Chave de idempotência (UUID v4): uma por tentativa de compra. Se a resposta do pedido
  /// se perder (Wi-Fi caiu, PC lento) e a pessoa confirmar de novo, a API devolve o MESMO pedido.
  static String novaChave() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<List<Pedido>> meus() async => (await api.get('/api/pedidos/meus') as List)
      .map((e) => Pedido.fromJson(e as Map<String, dynamic>))
      .toList();

  Future<void> cancelar(int id) => api.post('/api/pedidos/$id/cancelar');
}

// ----------------------------------------------------------------------------
// AVALIAÇÕES — as mesmas do site: só quem comprou avalia; texto com link ou termo
// bloqueado vai para a moderação do painel antes de aparecer.
// ----------------------------------------------------------------------------
class AvaliacaoServico {
  Future<List<Avaliacao>> listar(int produtoId) async => (await api.get('/api/produtos/$produtoId/avaliacoes') as List)
      .map((e) => Avaliacao.fromJson(e as Map<String, dynamic>))
      .toList();

  /// Devolve a mensagem da API ("Obrigado pela avaliação!" ou "...depois de revisada pela equipe.").
  Future<String> enviar(int produtoId, int nota, String? comentario) async {
    final r = await api.post('/api/produtos/$produtoId/avaliacoes', {
      'nota': nota,
      'comentario': (comentario ?? '').trim().isEmpty ? null : comentario!.trim(),
    }) as Map<String, dynamic>;
    return r['mensagem'] as String? ?? 'Avaliação enviada.';
  }
}

// ----------------------------------------------------------------------------
// CEP — ViaCEP (o mesmo serviço que o site usa) para preencher o endereço.
// ----------------------------------------------------------------------------
class CepServico {
  /// Só dígitos; null se não tiver 8.
  static String? normalizar(String cep) {
    final d = cep.replaceAll(RegExp(r'\D'), '');
    return d.length == 8 ? d : null;
  }

  /// null quando o CEP não existe ou o ViaCEP não respondeu (a pessoa digita à mão).
  Future<EnderecoCep?> buscar(String cep) async {
    final limpo = normalizar(cep);
    if (limpo == null) return null;
    try {
      final r = await http
          .get(Uri.parse('https://viacep.com.br/ws/$limpo/json/'))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      return EnderecoCep.fromViaCep(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

// Instâncias únicas compartilhadas pelas telas
final sessao = SessaoServico();
final carrinho = CarrinhoServico();
final catalogo = CatalogoServico();
final pedidos = PedidoServico();
final avaliacoes = AvaliacaoServico();
final cep = CepServico();
