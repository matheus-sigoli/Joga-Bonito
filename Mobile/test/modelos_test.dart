import 'package:flutter_test/flutter_test.dart';
import 'package:jogabonito_mobile/modelos/modelos.dart';

void main() {
  test('Produto lê o JSON da API e calcula promoção', () {
    final p = Produto.fromJson({
      'id': 3, 'nome': 'Camisa Corinthians 2026 Home', 'modelo': 'Torcedor', 'linha': 'Clube',
      'descricao': 'x', 'preco': 339.9, 'precoPromocional': 299.9, 'precoFinal': 299.9,
      'img': '../IMG/Produtos/3/1.jpg', 'destaque': true, 'categoria': 'Temporada 2026',
      'categoriaSlug': 'temporada-2026', 'estoque': 40, 'notaMedia': 0, 'totalAvaliacoes': 0,
    });
    expect(p.emPromocao, isTrue);
    expect(p.percentualDesconto, 12);
    expect(p.ehChuteira, isFalse);
  });

  test('Item do carrinho gera o formato do POST /api/pedidos', () {
    final i = ItemCarrinho(produtoId: 1, nome: 'Camisa', img: '', preco: 349.9, tamanho: 'M', quantidade: 2);
    expect(i.subtotal, closeTo(699.8, 0.001));
    expect(i.paraApi(), {'produtoId': 1, 'tamanho': 'M', 'quantidade': 2});
  });

  test('Pedido identifica etapa atual e se pode cancelar', () {
    final p = Pedido.fromJson({
      'id': 1, 'data': '2026-10-20T10:00:00', 'status': 'Em Separação', 'formaPagamento': 'PIX',
      'parcelas': 1, 'origem': 'Mobile', 'subtotal': 100, 'desconto': 0, 'frete': 19.9, 'total': 119.9,
      'itens': [], 'historico': [{'status': 'Pago', 'data': '2026-10-20T10:00:00'}],
    });
    expect(p.etapaAtual, 1);
    expect(p.podeCancelar, isFalse);
  });

  test('Chuteira traz marca e tipo de solado da planilha', () {
    final p = Produto.fromJson({
      'id': 29, 'nome': 'Nike Mercurial Vapor TF', 'modelo': 'Society · Grama sintética', 'linha': 'Society',
      'marca': 'Nike', 'solado': 'TF — society', 'descricao': 'x', 'preco': 599.9, 'precoFinal': 599.9,
      'img': '../IMG/Produtos/29/ilustracao.svg', 'destaque': true, 'categoria': 'Chuteiras',
      'categoriaSlug': 'chuteiras', 'estoque': 120, 'notaMedia': 0, 'totalAvaliacoes': 0,
    });
    expect(p.ehChuteira, isTrue);
    expect(p.rotulo, 'Nike · TF — society');
    expect(Produto.fromJson(p.toJson()).solado, 'TF — society');
  });

  test('Camisa usa linha, equipe e ano no rótulo', () {
    final p = Produto.fromJson({
      'id': 22, 'nome': 'Camisa Santos 2011 Retrô', 'linha': 'Clube', 'equipe': 'Santos', 'ano': 2011,
      'preco': 329.9, 'categoriaSlug': 'retro',
    });
    expect(p.rotulo, 'Clube · Santos 2011');
  });
}
