import 'package:flutter_test/flutter_test.dart';
import 'package:jogabonito_mobile/modelos/modelos.dart';
import 'package:jogabonito_mobile/servicos/api_cliente.dart';
import 'package:jogabonito_mobile/servicos/cofre.dart';
import 'package:jogabonito_mobile/servicos/servicos.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Servidor da API', () {
    test('aceita HTTPS em qualquer servidor', () {
      expect(ApiCliente.normalizarServidor('https://jogabonito-api.azurewebsites.net/'),
          'https://jogabonito-api.azurewebsites.net');
    });

    test('aceita HTTP só na rede local de desenvolvimento', () {
      expect(ApiCliente.normalizarServidor('10.0.2.2:5000'), 'http://10.0.2.2:5000');
      expect(ApiCliente.normalizarServidor('http://192.168.0.15:5000'), 'http://192.168.0.15:5000');
      expect(ApiCliente.normalizarServidor('http://172.20.1.2:5000'), 'http://172.20.1.2:5000');
    });

    test('recusa HTTP na internet e endereços estranhos', () {
      expect(() => ApiCliente.normalizarServidor('http://jogabonito-api.azurewebsites.net'),
          throwsA(isA<ApiException>()));
      expect(() => ApiCliente.normalizarServidor('ftp://192.168.0.2'), throwsA(isA<ApiException>()));
      expect(() => ApiCliente.normalizarServidor('https://usuario:senha@exemplo.com'), throwsA(isA<ApiException>()));
    });
  });

  group('Sessão', () {
    const usuarioJson = '{"id":2,"nome":"Matheus Sigoli","email":"matheus@estudante.com","role":"Cliente"}';

    test('token antigo em texto comum vai para o cofre e some do shared_preferences', () async {
      final expira = DateTime.now().add(const Duration(hours: 2)).toIso8601String();
      SharedPreferences.setMockInitialValues(
          {'jb_token': 'tok-antigo', 'jb_usuario': usuarioJson, 'jb_expira': expira});
      final cofre = CofreMemoria();
      final sessao = SessaoServico(cofre: cofre);

      await sessao.restaurar();

      expect(sessao.logado, isTrue);
      expect(await cofre.ler(), 'tok-antigo');
      expect((await SharedPreferences.getInstance()).getString('jb_token'), isNull);
    });

    test('sessão vencida é encerrada ao abrir o app', () async {
      final venceu = DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String();
      SharedPreferences.setMockInitialValues({'jb_usuario': usuarioJson, 'jb_expira': venceu});
      final cofre = CofreMemoria()..gravar('tok-velho');
      final sessao = SessaoServico(cofre: cofre);

      await sessao.restaurar();

      expect(sessao.logado, isFalse);
      expect(await cofre.ler(), isNull);
    });

    test('sair apaga o token do cofre', () async {
      SharedPreferences.setMockInitialValues({});
      final cofre = CofreMemoria()..gravar('tok');
      await SessaoServico(cofre: cofre).sair();
      expect(await cofre.ler(), isNull);
    });
  });

  group('Carrinho', () {
    final camisa = Produto.fromJson({
      'id': 13, 'nome': 'Camisa Brasil 1994 Retrô', 'linha': 'Seleção', 'preco': 299.9, 'precoFinal': 299.9,
      'categoriaSlug': 'retro',
    });

    test('soma itens iguais, limita a 10 e calcula frete', () async {
      SharedPreferences.setMockInitialValues({});
      final carrinho = CarrinhoServico();
      await carrinho.adicionar(camisa, 'M', 1);
      expect(carrinho.freteEstimado, 0);                 // R$ 299,90 ≥ R$ 299: frete grátis
      await carrinho.adicionar(camisa, 'M', 15);
      expect(carrinho.itens.single.quantidade, 10);
      await carrinho.adicionar(camisa, 'G', 1);
      expect(carrinho.itens.length, 2);
    });

    test('continua salvo no aparelho (sobrevive a uma compra que falhou)', () async {
      SharedPreferences.setMockInitialValues({});
      await CarrinhoServico().adicionar(camisa, 'P', 2);
      final reaberto = CarrinhoServico();
      await reaberto.carregar();
      expect(reaberto.quantidade, 2);
    });
  });
}
