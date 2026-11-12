// Chave de idempotência do pedido: um UUID v4 novo por tentativa de compra.
// A API (sp_RegistrarPedido) usa a chave para não gravar o mesmo pedido duas vezes
// quando a resposta se perde e o cliente confirma de novo.
import 'package:flutter_test/flutter_test.dart';
import 'package:jogabonito_mobile/servicos/servicos.dart';

void main() {
  final uuidV4 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

  test('gera UUID v4 válido (o servidor só aceita Guid)', () {
    for (var i = 0; i < 50; i++) {
      expect(PedidoServico.novaChave(), matches(uuidV4));
    }
  });

  test('cada tentativa de compra tem uma chave diferente', () {
    final chaves = {for (var i = 0; i < 200; i++) PedidoServico.novaChave()};
    expect(chaves.length, 200);
  });
}
