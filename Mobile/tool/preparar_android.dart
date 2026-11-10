// ============================================================================
// Prepara a pasta android/ gerada por "flutter create" para o Joga Bonito.
//   dart run tool/preparar_android.dart
//
// * Build de DEPURAÇÃO (flutter run): libera HTTP para testar com a API no PC
//   (emulador 10.0.2.2 ou celular na mesma rede Wi-Fi).
// * Build de PRODUÇÃO (APK release): nada é liberado — o Android só aceita
//   HTTPS, além da regra do próprio app (ApiCliente.normalizarServidor).
// * Com --rede-local: gera o APK de DEMONSTRAÇÃO para instalar no celular e usar
//   com a API no PC pela rede Wi-Fi (HTTP). O próprio app continua recusando HTTP
//   fora da rede local (ApiCliente.normalizarServidor) — ver ADR 009.
// * Nome do app na tela do celular: "Joga Bonito".
// * Garante a permissão de internet no manifesto principal.
// * Apaga o test/widget_test.dart de exemplo do flutter create (usa MyApp).
// Pode ser executado várias vezes: só altera o que falta.
// ============================================================================
import 'dart:io';

void main(List<String> args) {
  final redeLocal = args.contains('--rede-local');
  final principal = File('android/app/src/main/AndroidManifest.xml');
  final depuracao = File('android/app/src/debug/AndroidManifest.xml');
  if (!principal.existsSync()) {
    stderr.writeln('android/ não encontrado. Rode antes: flutter create --project-name jogabonito_mobile --org br.unip.pim .');
    exit(1);
  }

  // 1. Internet no app de produção
  var texto = principal.readAsStringSync();
  if (!texto.contains('android.permission.INTERNET')) {
    texto = texto.replaceFirstMapped(RegExp(r'<manifest[^>]*>'),
        (m) => '${m[0]}\n    <uses-permission android:name="android.permission.INTERNET"/>');
    principal.writeAsStringSync(texto);
    stdout.writeln('[ok] Permissão de internet adicionada ao manifesto principal');
  }
  texto = principal.readAsStringSync();
  if (texto.contains('android:label="jogabonito_mobile"')) {
    principal.writeAsStringSync(texto.replaceAll('android:label="jogabonito_mobile"', 'android:label="Joga Bonito"'));
    stdout.writeln('[ok] Nome do app: Joga Bonito');
  }
  texto = principal.readAsStringSync();
  if (redeLocal) {
    if (!texto.contains('usesCleartextTraffic="true"')) {
      principal.writeAsStringSync(texto.replaceFirst('<application', '<application android:usesCleartextTraffic="true"'));
      stdout.writeln('[ok] APK rede local: HTTP liberado para falar com a API no PC (Wi-Fi)');
    }
  } else if (texto.contains('usesCleartextTraffic="true"')) {
    principal.writeAsStringSync(texto.replaceAll(' android:usesCleartextTraffic="true"', '').replaceAll('android:usesCleartextTraffic="true"', ''));
    stdout.writeln('[ok] HTTP removido do manifesto de produção (só HTTPS)');
  }

  // 2. HTTP só na depuração
  if (!depuracao.existsSync()) {
    depuracao.createSync(recursive: true);
    depuracao.writeAsStringSync('''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
</manifest>
''');
  }
  var debug = depuracao.readAsStringSync();
  if (!debug.contains('usesCleartextTraffic')) {
    debug = debug.replaceFirst('</manifest>',
        '    <!-- Só na depuração: API local em HTTP (PC/emulador). O APK de produção exige HTTPS. -->\n'
        '    <application android:usesCleartextTraffic="true"/>\n'
        '</manifest>');
    depuracao.writeAsStringSync(debug);
    stdout.writeln('[ok] HTTP liberado apenas no build de depuração');
  }
  // 3. "flutter create" gera um teste de exemplo que usa MyApp (não existe aqui) e quebraria flutter test
  final exemplo = File('test/widget_test.dart');
  if (exemplo.existsSync() && exemplo.readAsStringSync().contains('MyApp')) {
    exemplo.deleteSync();
    stdout.writeln('[ok] Teste de exemplo do flutter create removido (usava MyApp)');
  }

  stdout.writeln(redeLocal
      ? 'Android pronto (rede local). flutter build apk --release  → instale no celular e use iniciar-com-celular.bat no PC'
      : 'Android pronto. Produção: flutter build apk --release --dart-define=API_URL=https://<sua-loja>.azurewebsites.net');
}
