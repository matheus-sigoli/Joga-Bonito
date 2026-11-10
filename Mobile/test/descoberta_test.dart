// Testes da descoberta da loja na rede, das avaliações e do CEP (sem rede: só funções puras).
import 'package:flutter_test/flutter_test.dart';
import 'package:jogabonito_mobile/modelos/modelos.dart';
import 'package:jogabonito_mobile/servicos/descoberta.dart';
import 'package:jogabonito_mobile/servicos/servicos.dart';

void main() {
  group('Descoberta da loja na rede Wi-Fi', () {
    test('só redes privadas', () {
      expect(DescobertaLoja.ipPrivado('192.168.0.23'), isTrue);
      expect(DescobertaLoja.ipPrivado('10.0.2.15'), isTrue);
      expect(DescobertaLoja.ipPrivado('172.20.10.4'), isTrue); // hotspot do iPhone
      expect(DescobertaLoja.ipPrivado('172.32.0.1'), isFalse);
      expect(DescobertaLoja.ipPrivado('8.8.8.8'), isFalse);
      expect(DescobertaLoja.ipPrivado('192.168.0'), isFalse);
      expect(DescobertaLoja.ipPrivado('192.168.0.300'), isFalse);
    });

    test('testa a mesma rede /24, sem o próprio celular', () {
      final c = DescobertaLoja.candidatos('192.168.0.23');
      expect(c, hasLength(253));
      expect(c.first, '192.168.0.1');
      expect(c, isNot(contains('192.168.0.23')));
      expect(c, contains('192.168.0.254'));
      expect(c.every((ip) => ip.startsWith('192.168.0.')), isTrue);
    });

    test('no emulador Android o PC (10.0.2.2) vem primeiro e não repete', () {
      final c = DescobertaLoja.candidatos('10.0.2.15');
      expect(c.first, '10.0.2.2');
      expect(c.where((ip) => ip == '10.0.2.2'), hasLength(1));
    });

    test('rede pública não é varrida', () {
      expect(DescobertaLoja.candidatos('200.150.10.27'), isEmpty);
    });
  });

  group('Avaliações', () {
    test('lê a resposta da API e trata comentário vazio', () {
      final a = Avaliacao.fromJson({'cliente': 'Matheus', 'nota': 5, 'comentario': '  ', 'data': '2026-11-01T10:00:00'});
      expect(a.cliente, 'Matheus');
      expect(a.nota, 5);
      expect(a.comentario, isNull);
      final b = Avaliacao.fromJson({'cliente': 'Ana', 'nota': 9, 'comentario': 'Ótima', 'data': '2026-11-02T10:00:00'});
      expect(b.nota, 5); // nunca passa de 5 estrelas
      expect(b.comentario, 'Ótima');
    });
  });

  group('CEP (ViaCEP)', () {
    test('normaliza só com 8 dígitos', () {
      expect(CepServico.normalizar('01310-100'), '01310100');
      expect(CepServico.normalizar('0131010'), isNull);
    });

    test('lê o endereço e reconhece CEP inexistente', () {
      final e = EnderecoCep.fromViaCep(
          {'logradouro': 'Avenida Paulista', 'bairro': 'Bela Vista', 'localidade': 'São Paulo', 'uf': 'SP'});
      expect(e!.rua, 'Avenida Paulista');
      expect(e.uf, 'SP');
      expect(EnderecoCep.fromViaCep({'erro': true}), isNull);
      expect(EnderecoCep.fromViaCep({'erro': 'true'}), isNull);
    });
  });
}
