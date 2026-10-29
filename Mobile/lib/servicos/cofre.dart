// ============================================================================
// Cofre do token JWT. O token é um SEGREDO: fica no armazenamento seguro do
// sistema (Android Keystore / iOS Keychain) via flutter_secure_storage — não no
// shared_preferences, que é um arquivo comum. Preferências (endereço do servidor,
// carrinho, catálogo offline) continuam no shared_preferences.
// ============================================================================
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class CofreToken {
  Future<String?> ler();
  Future<void> gravar(String token);
  Future<void> apagar();
}

class CofreSeguro implements CofreToken {
  static const _chave = 'jb_token';
  static const _armazenamento = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  @override
  Future<String?> ler() => _armazenamento.read(key: _chave);

  @override
  Future<void> gravar(String token) => _armazenamento.write(key: _chave, value: token);

  @override
  Future<void> apagar() => _armazenamento.delete(key: _chave);
}

/// Cofre em memória, usado nos testes automatizados.
class CofreMemoria implements CofreToken {
  String? _token;

  @override
  Future<String?> ler() async => _token;

  @override
  Future<void> gravar(String token) async => _token = token;

  @override
  Future<void> apagar() async => _token = null;
}
