// ============================================================================
// Modelos de dados do app — espelham os DTOs da API .NET (JSON camelCase).
// ============================================================================

double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();

class Usuario {
  final int id;
  final String nome;
  final String email;
  final String role;

  const Usuario({required this.id, required this.nome, required this.email, required this.role});

  bool get ehAdmin => role == 'Admin';
  String get primeiroNome => nome.split(' ').first;

  factory Usuario.fromJson(Map<String, dynamic> j) =>
      Usuario(id: j['id'] as int, nome: j['nome'] as String, email: j['email'] as String, role: j['role'] as String);

  Map<String, dynamic> toJson() => {'id': id, 'nome': nome, 'email': email, 'role': role};
}

class Produto {
  final int id;
  final String nome;
  final String modelo;
  final String linha;
  final String? equipe;
  final int? ano;
  final String? marca;   // chuteiras: Nike, adidas
  final String? solado;  // chuteiras: FG — campo, TF — society, IC — quadra
  final String descricao;
  final double preco;
  final double? precoPromocional;
  final double precoFinal;
  final String img;
  final bool destaque;
  final String categoria;
  final String categoriaSlug;
  final int estoque;
  final double notaMedia;
  final int totalAvaliacoes;

  const Produto({
    required this.id, required this.nome, required this.modelo, required this.linha, this.equipe, this.ano,
    this.marca, this.solado, required this.descricao, required this.preco, this.precoPromocional, required this.precoFinal,
    required this.img, required this.destaque, required this.categoria, required this.categoriaSlug,
    required this.estoque, required this.notaMedia, required this.totalAvaliacoes,
  });

  bool get emPromocao => precoPromocional != null && precoPromocional! < preco;
  bool get ehChuteira => categoriaSlug == 'chuteiras';
  int get percentualDesconto => emPromocao ? ((1 - precoPromocional! / preco) * 100).round() : 0;

  /// Mesmo rótulo da loja web: "Nike · TF — society" ou "Clube · Flamengo 1981".
  String get rotulo {
    if (marca != null) return solado != null ? '$marca · $solado' : marca!;
    if (equipe != null) return '$linha · $equipe${ano != null ? ' $ano' : ''}';
    return modelo;
  }

  factory Produto.fromJson(Map<String, dynamic> j) => Produto(
        id: j['id'] as int,
        nome: j['nome'] as String,
        modelo: j['modelo'] as String? ?? '',
        linha: j['linha'] as String? ?? '',
        equipe: j['equipe'] as String?,
        ano: j['ano'] as int?,
        marca: j['marca'] as String?,
        solado: j['solado'] as String?,
        descricao: j['descricao'] as String? ?? '',
        preco: _d(j['preco']),
        precoPromocional: j['precoPromocional'] == null ? null : _d(j['precoPromocional']),
        precoFinal: _d(j['precoFinal'] ?? j['preco']),
        img: j['img'] as String? ?? '',
        destaque: j['destaque'] as bool? ?? false,
        categoria: j['categoria'] as String? ?? '',
        categoriaSlug: j['categoriaSlug'] as String? ?? '',
        estoque: j['estoque'] as int? ?? 0,
        notaMedia: _d(j['notaMedia']),
        totalAvaliacoes: j['totalAvaliacoes'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'nome': nome, 'modelo': modelo, 'linha': linha, 'equipe': equipe, 'ano': ano,
        'marca': marca, 'solado': solado, 'descricao': descricao, 'preco': preco, 'precoPromocional': precoPromocional, 'precoFinal': precoFinal,
        'img': img, 'destaque': destaque, 'categoria': categoria, 'categoriaSlug': categoriaSlug,
        'estoque': estoque, 'notaMedia': notaMedia, 'totalAvaliacoes': totalAvaliacoes,
      };
}

class TamanhoEstoque {
  final String tamanho;
  final int quantidade;
  const TamanhoEstoque(this.tamanho, this.quantidade);

  factory TamanhoEstoque.fromJson(Map<String, dynamic> j) =>
      TamanhoEstoque(j['tamanho'] as String, j['quantidade'] as int);
}

class ProdutoDetalhe {
  final Produto produto;
  final String tipo;
  final List<String> imagens;
  final List<TamanhoEstoque> tamanhos;

  const ProdutoDetalhe({required this.produto, required this.tipo, required this.imagens, required this.tamanhos});

  factory ProdutoDetalhe.fromJson(Map<String, dynamic> j) => ProdutoDetalhe(
        produto: Produto.fromJson(j['produto'] as Map<String, dynamic>),
        tipo: j['tipo'] as String,
        imagens: (j['imgs'] as List).cast<String>(),
        tamanhos: (j['tamanhos'] as List).map((t) => TamanhoEstoque.fromJson(t as Map<String, dynamic>)).toList(),
      );
}

class ItemCarrinho {
  final int produtoId;
  final String nome;
  final String img;
  final double preco;
  final String tamanho;
  int quantidade;

  ItemCarrinho({
    required this.produtoId, required this.nome, required this.img, required this.preco,
    required this.tamanho, required this.quantidade,
  });

  double get subtotal => preco * quantidade;

  factory ItemCarrinho.fromJson(Map<String, dynamic> j) => ItemCarrinho(
        produtoId: j['produtoId'] as int, nome: j['nome'] as String, img: j['img'] as String,
        preco: _d(j['preco']), tamanho: j['tamanho'] as String, quantidade: j['quantidade'] as int);

  Map<String, dynamic> toJson() =>
      {'produtoId': produtoId, 'nome': nome, 'img': img, 'preco': preco, 'tamanho': tamanho, 'quantidade': quantidade};

  /// Formato esperado por POST /api/pedidos.
  Map<String, dynamic> paraApi() => {'produtoId': produtoId, 'tamanho': tamanho, 'quantidade': quantidade};
}

class ResumoPedido {
  final double subtotal, desconto, frete, total;
  final String? cupom;

  /// 1% dos produtos destinado ao programa Joga Junto (calculado pela API).
  final double jogaJunto;
  const ResumoPedido(this.subtotal, this.desconto, this.frete, this.total, this.cupom, {this.jogaJunto = 0});

  factory ResumoPedido.fromJson(Map<String, dynamic> j) => ResumoPedido(
      _d(j['subtotal']), _d(j['desconto']), _d(j['frete']), _d(j['total']), j['cupom'] as String?,
      jogaJunto: _d(j['jogaJunto']));
}

class ItemPedido {
  final int produtoId;
  final String nome;
  final String img;
  final String tamanho;
  final int qtd;
  final double preco;
  const ItemPedido(this.produtoId, this.nome, this.img, this.tamanho, this.qtd, this.preco);

  factory ItemPedido.fromJson(Map<String, dynamic> j) => ItemPedido(j['produtoId'] as int, j['nome'] as String,
      j['img'] as String, j['tamanho'] as String, j['qtd'] as int, _d(j['preco']));
}

class Pedido {
  final int id;
  final DateTime data;
  final String status;
  final String formaPagamento;
  final int parcelas;
  final String? codigoRastreio;
  final String origem;
  final double subtotal, desconto, frete, total;
  final List<ItemPedido> itens;
  final List<MapEntry<String, DateTime>> historico;

  const Pedido({
    required this.id, required this.data, required this.status, required this.formaPagamento,
    required this.parcelas, this.codigoRastreio, required this.origem, required this.subtotal,
    required this.desconto, required this.frete, required this.total, required this.itens, required this.historico,
  });

  static const etapas = ['Pago', 'Em Separação', 'Enviado', 'Entregue'];
  bool get cancelado => status == 'Cancelado';
  bool get podeCancelar => status == 'Pago' || status == 'Aguardando Pagamento';
  int get etapaAtual => etapas.indexOf(status);

  factory Pedido.fromJson(Map<String, dynamic> j) => Pedido(
        id: j['id'] as int,
        data: DateTime.parse(j['data'] as String),
        status: j['status'] as String,
        formaPagamento: j['formaPagamento'] as String,
        parcelas: j['parcelas'] as int? ?? 1,
        codigoRastreio: j['codigoRastreio'] as String?,
        origem: j['origem'] as String? ?? 'Web',
        subtotal: _d(j['subtotal']),
        desconto: _d(j['desconto']),
        frete: _d(j['frete']),
        total: _d(j['total']),
        itens: (j['itens'] as List).map((i) => ItemPedido.fromJson(i as Map<String, dynamic>)).toList(),
        historico: (j['historico'] as List? ?? [])
            .map((h) => MapEntry(h['status'] as String, DateTime.parse(h['data'] as String)))
            .toList(),
      );
}
