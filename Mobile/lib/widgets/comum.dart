// ============================================================================
// Tema, formatação e widgets reutilizáveis.
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../modelos/modelos.dart';
import '../servicos/api_cliente.dart';

class Cores {
  static const verde = Color(0xFF0E552A);
  static const verdeClaro = Color(0xFF177A3D);
  static const amarelo = Color(0xFFFCCA0F);
  static const fundo = Color(0xFF060D09);
  static const superficie = Color(0xFF0C1912);
  static const superficie2 = Color(0xFF122419);
  static const textoSuave = Color(0xFFB5C2B8);
  static const erro = Color(0xFFFF7A7A);
  static const sucesso = Color(0xFF5FE08D);
}

ThemeData temaJogaBonito() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Cores.verde,
      brightness: Brightness.dark,
      primary: Cores.amarelo,
      onPrimary: Colors.black,
      secondary: Cores.verdeClaro,
      surface: Cores.superficie,
      error: Cores.erro,
    ),
    scaffoldBackgroundColor: Cores.fundo,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(backgroundColor: Cores.fundo, centerTitle: false, elevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Cores.superficie2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Cores.amarelo, width: 2)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Cores.amarelo,
        foregroundColor: Colors.black,
        minimumSize: const Size.fromHeight(50),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Cores.superficie,
      indicatorColor: Cores.amarelo.withValues(alpha: 0.2),
    ),
  );
}

final formaCard = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(14),
  side: const BorderSide(color: Color(0x24FCCA0F)),
);

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
String brl(num valor) => _moeda.format(valor);

String dataHora(DateTime d) {
  String dois(int n) => n.toString().padLeft(2, '0');
  final l = d.toLocal();
  return '${dois(l.day)}/${dois(l.month)}/${l.year} ${dois(l.hour)}:${dois(l.minute)}';
}

void mostrarMensagem(BuildContext context, String texto, {bool erro = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: erro ? const Color(0xFF3A1212) : Cores.verde,
      behavior: SnackBarBehavior.floating,
    ));
}

/// Imagem vinda da API com placeholder e fallback para o escudo da marca.
/// Produtos sem foto usam a ilustração em SVG (camisa nas cores do time,
/// chuteira com a sola do piso) — renderizada pelo pacote flutter_svg.
class ImagemProduto extends StatelessWidget {
  final String caminho;
  final BoxFit fit;
  const ImagemProduto(this.caminho, {super.key, this.fit = BoxFit.cover});

  static Widget _reserva() => Container(
        color: Cores.superficie2,
        padding: const EdgeInsets.all(24),
        child: Opacity(opacity: 0.5, child: Image.asset('assets/escudo.png')),
      );

  @override
  Widget build(BuildContext context) {
    final url = ApiCliente.instancia.urlImagem(caminho);
    if (url.toLowerCase().endsWith('.svg')) {
      return SvgPicture.network(
        url,
        fit: fit,
        placeholderBuilder: (_) => Container(color: Cores.superficie2),
      );
    }
    return Image.network(
      url,
      fit: fit,
      loadingBuilder: (c, child, prog) => prog == null ? child : Container(color: Cores.superficie2),
      errorBuilder: (c, e, s) => _reserva(),
    );
  }
}

class CardProduto extends StatelessWidget {
  final Produto produto;
  final VoidCallback onTap;
  const CardProduto({super.key, required this.produto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = produto;
    return Semantics(
      button: true,
      label: '${p.nome}, ${brl(p.precoFinal)}${p.estoque == 0 ? ', esgotado' : ''}',
      child: Card(
        color: Cores.superficie,
        elevation: 0,
        shape: formaCard,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(fit: StackFit.expand, children: [
                  Opacity(opacity: p.estoque == 0 ? 0.45 : 1, child: ImagemProduto(p.img)),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Wrap(spacing: 4, children: [
                      if (p.emPromocao) _Selo('-${p.percentualDesconto}%', fundo: Cores.amarelo, corTexto: Colors.black),
                      if (p.estoque == 0) const _Selo('Esgotado'),
                    ]),
                  ),
                  Positioned(top: 8, right: 8, child: _Selo(p.linha)),
                ]),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.nome, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const Spacer(),
                      if (p.emPromocao)
                        Text(brl(p.preco),
                            style: const TextStyle(
                                decoration: TextDecoration.lineThrough, color: Cores.textoSuave, fontSize: 11)),
                      Text(brl(p.precoFinal),
                          style: const TextStyle(color: Cores.amarelo, fontWeight: FontWeight.w800, fontSize: 16)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Selo extends StatelessWidget {
  final String texto;
  final Color fundo;
  final Color corTexto;
  const _Selo(this.texto, {this.fundo = const Color(0xCC060D09), this.corTexto = Colors.white});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(99)),
        child: Text(texto.toUpperCase(),
            style: TextStyle(color: corTexto, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      );
}

class EstadoVazio extends StatelessWidget {
  final IconData icone;
  final String mensagem;
  final Widget? acao;
  const EstadoVazio({super.key, required this.icone, required this.mensagem, this.acao});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icone, size: 56, color: Cores.textoSuave),
            const SizedBox(height: 12),
            Text(mensagem, textAlign: TextAlign.center, style: const TextStyle(color: Cores.textoSuave)),
            if (acao != null) ...[const SizedBox(height: 16), acao!],
          ]),
        ),
      );
}
