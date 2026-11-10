// ============================================================================
// DESCOBERTA — acha a loja (API no PC) na mesma rede Wi-Fi do celular, sem digitar IP.
//
// Como funciona: o celular sabe o próprio IP (ex.: 192.168.0.23). O PC com a API
// está na mesma rede (192.168.0.1 a 192.168.0.254). O app pergunta a cada endereço,
// em lotes paralelos e com tempo curto, "GET http://IP:5000/api/loja" e fica com o
// primeiro que responder {"loja": "Joga Bonito"}.
//
// No PC, a API precisa estar aberta para a rede: iniciar-com-celular.bat.
// No emulador Android a rede é 10.0.2.x e o PC é 10.0.2.2 — entra na mesma busca.
// ============================================================================
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class DescobertaLoja {
  static const portaPadrao = 5000;

  /// true para IPv4 de rede privada (onde o HTTP sem cadeado é aceito pelo app).
  static bool ipPrivado(String ip) {
    final p = ip.split('.').map(int.tryParse).toList();
    if (p.length != 4 || p.any((x) => x == null || x < 0 || x > 255)) return false;
    final a = p[0]!, b = p[1]!;
    return a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
  }

  /// Endereços a testar a partir do IP do celular: a mesma rede /24, sem o próprio
  /// celular, começando pelos mais comuns para PCs (roteador costuma ser o .1).
  /// Função pura (testada em test/descoberta_test.dart).
  static List<String> candidatos(String ipCelular) {
    if (!ipPrivado(ipCelular)) return const [];
    final partes = ipCelular.split('.');
    final prefixo = '${partes[0]}.${partes[1]}.${partes[2]}';
    final proprio = int.parse(partes[3]);
    final lista = <String>[
      if (prefixo == '10.0.2') '10.0.2.2', // emulador Android: o PC
      for (var i = 1; i <= 254; i++)
        if (i != proprio && !(prefixo == '10.0.2' && i == 2)) '$prefixo.$i',
    ];
    return lista;
  }

  /// IPv4 privados deste aparelho (Wi-Fi ou rede do emulador).
  static Future<List<String>> ipsDoAparelho() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      return [
        for (final i in interfaces)
          for (final e in i.addresses)
            if (ipPrivado(e.address)) e.address,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Confirma que no endereço está a API da Joga Bonito (e não outro serviço).
  static Future<bool> ehLoja(String base, {Duration limite = const Duration(milliseconds: 900), http.Client? cliente}) async {
    final c = cliente ?? http.Client();
    try {
      final r = await c.get(Uri.parse('$base/api/loja'), headers: const {'Accept': 'application/json'}).timeout(limite);
      if (r.statusCode != 200) return false;
      final dados = jsonDecode(utf8.decode(r.bodyBytes));
      return dados is Map && dados['loja'] == 'Joga Bonito';
    } catch (_) {
      return false;
    } finally {
      if (cliente == null) c.close();
    }
  }

  /// Procura a loja na rede. Devolve "http://IP:5000" ou null.
  /// [progresso] recebe (testados, total) para a barra da tela.
  static Future<String?> procurar({
    int porta = portaPadrao,
    void Function(int testados, int total)? progresso,
    int paralelos = 32,
  }) async {
    final ips = await ipsDoAparelho();
    final candidatos = <String>{for (final ip in ips) ...DescobertaLoja.candidatos(ip)}.toList();
    if (candidatos.isEmpty) return null;

    final cliente = http.Client();
    var testados = 0;
    try {
      for (var i = 0; i < candidatos.length; i += paralelos) {
        final lote = candidatos.skip(i).take(paralelos).toList();
        final achados = await Future.wait(lote.map((ip) async {
          final base = 'http://$ip:$porta';
          return await ehLoja(base, cliente: cliente) ? base : null;
        }));
        testados += lote.length;
        progresso?.call(testados, candidatos.length);
        final achado = achados.whereType<String>().firstOrNull;
        if (achado != null) return achado;
      }
      return null;
    } finally {
      cliente.close();
    }
  }
}
