import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jogabonito_mobile/modelos/modelos.dart';
import 'package:jogabonito_mobile/widgets/comum.dart';

/// O leitor de tela (TalkBack/VoiceOver) precisa anunciar nome, preço e disponibilidade
/// do produto num rótulo só, e o card precisa se comportar como botão.
void main() {
  Produto produto({int estoque = 20}) => Produto.fromJson({
        'id': 13, 'nome': 'Camisa Brasil 1994 Retrô', 'linha': 'Seleção', 'preco': 299.9, 'precoFinal': 299.9,
        'categoriaSlug': 'retro', 'img': '../IMG/Produtos/13/1.jpg', 'estoque': estoque,
      });

  Future<void> montar(WidgetTester tester, Produto p) => tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: 220, height: 340, child: CardProduto(produto: p, onTap: () {}))),
        ),
      ));

  testWidgets('card anuncia nome e preço como botão', (tester) async {
    final semantica = tester.ensureSemantics();
    await montar(tester, produto());
    final rotulo = find.bySemanticsLabel(RegExp(r'Camisa Brasil 1994 Retrô, R\$'));
    expect(rotulo, findsOneWidget);
    expect(tester.getSemantics(rotulo), isSemantics(isButton: true));
    semantica.dispose();
  });

  testWidgets('produto esgotado é anunciado como esgotado', (tester) async {
    final semantica = tester.ensureSemantics();
    await montar(tester, produto(estoque: 0));
    expect(find.bySemanticsLabel(RegExp('esgotado')), findsOneWidget);
    semantica.dispose();
  });
}
