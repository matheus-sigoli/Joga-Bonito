// O Perfil mostra a data do catálogo offline. Ele fica aberto num IndexedStack desde
// o início do app, então depende do aviso (ValueNotifier) para mostrar a data
// quando o catálogo carregar depois — achado no vídeo de teste de 13/11/2026.
import 'package:flutter_test/flutter_test.dart';
import 'package:jogabonito_mobile/servicos/servicos.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sem catálogo salvo: data nula', () async {
    SharedPreferences.setMockInitialValues({});
    final c = CatalogoServico();
    expect(await c.ultimaSincronizacao(), isNull);
    expect(c.sincronizado.value, isNull);
  });

  test('catálogo salvo: a data chega a quem estiver ouvindo', () async {
    SharedPreferences.setMockInitialValues({'jb_cache_data': '2026-11-13T19:27:00.000'});
    final c = CatalogoServico();
    DateTime? recebido;
    c.sincronizado.addListener(() => recebido = c.sincronizado.value);
    await c.ultimaSincronizacao();
    expect(recebido, DateTime(2026, 11, 13, 19, 27));
  });
}
