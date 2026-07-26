import 'package:flutter_test/flutter_test.dart';
import 'package:inspirat/app.dart';

void main() {
  test('el usuario cumple las mismas reglas que la API', () {
    expect(validateUsername('autor_2026'), isNull);
    expect(validateUsername('ab'), isNotNull);
    expect(validateUsername('autor con espacios'), isNotNull);
    expect(validateUsername('josé'), isNotNull);
  });

  test('correo, nombre visible y contraseña se validan antes de enviar', () {
    expect(validateEmail('autora@example.com'), isNull);
    expect(validateEmail('correo-incompleto@'), isNotNull);
    expect(validateDisplayName('Autora'), isNull);
    expect(validateDisplayName('   '), isNotNull);
    expect(validatePassword('clave-segura-2026'), isNull);
    expect(validatePassword('corta'), isNotNull);
  });
}
