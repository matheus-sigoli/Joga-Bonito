// ============================================================================
// Cliente HTTP da API REST .NET — envia o token JWT e traduz erros.
// ============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final String mensagem;
  final int status;
  const ApiException(this.mensagem, this.status);

  bool get semConexao => status == 0;

  @override
  String toString() => mensagem;
}

class ApiCliente {
  ApiCliente._();
  static final ApiCliente instancia = ApiCliente._();

  /// Endereço padrão, definido na compilação:
  ///  - APK de produção:  flutter build apk --dart-define=API_URL=https://<loja>.azurewebsites.net
  ///  - Sem API_URL (desenvolvimento): http://10.0.2.2:5000, que no emulador Android aponta para o PC.
  ///  - Celular físico na rede local: em Perfil > Servidor da API, http://IP-DO-PC:5000.
  static const String enderecoPadrao = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:5000');
  static const _chaveEndereco = 'jb_servidor';

  String baseUrl = enderecoPadrao;
  String? token;

  /// Validade do token (vem do login). Vencido, o app nem envia: encerra a sessão.
  DateTime? tokenExpiraEm;

  /// Chamado quando a API recusa o token (expirou, senha trocada em outro aparelho, conta desativada).
  void Function()? aoExpirarSessao;

  Future<void> carregarConfiguracao() async {
    final prefs = await SharedPreferences.getInstance();
    final salvo = prefs.getString(_chaveEndereco);
    // Endereço salvo em outra versão que hoje não seria aceito (ex.: HTTP fora da rede local): volta ao padrão
    try {
      baseUrl = salvo == null ? enderecoPadrao : normalizarServidor(salvo);
    } on ApiException {
      baseUrl = enderecoPadrao;
      await prefs.remove(_chaveEndereco);
    }
  }

  Future<void> alterarServidor(String url) async {
    final limpo = normalizarServidor(url);
    baseUrl = limpo;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chaveEndereco, limpo);
  }

  /// Aceita só endereços seguros para mandar senha e token:
  ///  - HTTPS em qualquer servidor (produção, Azure);
  ///  - HTTP apenas na rede local de desenvolvimento (emulador, localhost, 192.168.x.x, 10.x.x.x, 172.16-31.x.x).
  /// Lança [ApiException] com a explicação quando o endereço não é aceito.
  static String normalizarServidor(String url) {
    var limpo = url.trim();
    while (limpo.endsWith('/')) {
      limpo = limpo.substring(0, limpo.length - 1);
    }
    if (!limpo.contains('://')) limpo = 'http://$limpo';
    final uri = Uri.tryParse(limpo);
    if (uri == null || uri.host.isEmpty || !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.hasQuery || uri.userInfo.isNotEmpty) {
      throw const ApiException('Endereço inválido. Exemplo: https://jogabonito-api.azurewebsites.net', 0);
    }
    if (uri.scheme == 'http' && !_redeLocal(uri.host)) {
      throw const ApiException('Fora da rede local use HTTPS (https://...). HTTP só é aceito para o PC na mesma rede.', 0);
    }
    return limpo;
  }

  static bool _redeLocal(String host) {
    if (host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2') return true;
    final partes = host.split('.').map(int.tryParse).toList();
    if (partes.length != 4 || partes.any((p) => p == null || p < 0 || p > 255)) return false;
    final a = partes[0]!, b = partes[1]!;
    return a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
  }

  /// Converte "../IMG/Produtos/1/1.jpg" (caminho do site) em URL absoluta.
  String urlImagem(String caminho) {
    if (caminho.startsWith('http')) return caminho;
    final relativo = caminho.replaceFirst(RegExp(r'^(\.\./|/)+'), '');
    return Uri.encodeFull('$baseUrl/$relativo');
  }

  Future<dynamic> get(String caminho) => _enviar('GET', caminho);
  Future<dynamic> post(String caminho, [Object? corpo]) => _enviar('POST', caminho, corpo);
  Future<dynamic> put(String caminho, [Object? corpo]) => _enviar('PUT', caminho, corpo);

  Future<dynamic> _enviar(String metodo, String caminho, [Object? corpo]) async {
    if (token != null && tokenExpiraEm != null && tokenExpiraEm!.isBefore(DateTime.now())) {
      aoExpirarSessao?.call();
      throw const ApiException('Sua sessão expirou. Entre novamente.', 401);
    }
    final uri = Uri.parse('$baseUrl$caminho');
    final headers = <String, String>{
      'Accept': 'application/json',
      if (corpo != null) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    http.Response resp;
    try {
      final req = http.Request(metodo, uri)..headers.addAll(headers);
      if (corpo != null) req.body = jsonEncode(corpo);
      resp = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 12)));
    } on TimeoutException {
      throw const ApiException('O servidor demorou para responder. Tente de novo.', 0);
    } catch (_) {
      throw ApiException('Sem conexão com a API ($baseUrl). Confira o endereço em Perfil > Servidor.', 0);
    }

    final texto = utf8.decode(resp.bodyBytes);
    dynamic dados;
    try {
      dados = texto.isEmpty ? null : jsonDecode(texto);
    } on FormatException {
      dados = texto; // respostas em texto puro, como GET /health
    }

    if (resp.statusCode >= 200 && resp.statusCode < 300) return dados;
    if (resp.statusCode == 401 && token != null) aoExpirarSessao?.call();

    final mensagem = (dados is Map && dados['mensagem'] != null)
        ? dados['mensagem'] as String
        : switch (resp.statusCode) {
            401 => 'Faça login para continuar.',
            403 => 'Você não tem permissão para esta ação.',
            404 => 'Não encontrado.',
            429 => 'Muitas tentativas. Aguarde um minuto.',
            _ => 'Erro ao processar a solicitação (${resp.statusCode}).',
          };
    throw ApiException(mensagem, resp.statusCode);
  }
}
