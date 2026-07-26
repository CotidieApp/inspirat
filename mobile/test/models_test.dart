import 'package:flutter_test/flutter_test.dart';
import 'package:inspirat/data/models.dart';

void main() {
  test('countWords tolera espacios y líneas vacías', () {
    expect(countWords(''), 0);
    expect(countWords('  La lluvia\nrecuerda   nombres. '), 4);
  });

  test('un documento conserva el identificador local y cuenta palabras', () {
    final document = WritingDocument(
      clientId: 'local-document',
      projectClientId: 'local-project',
      title: 'Capítulo 1',
      content: 'El texto queda aquí.',
      updatedAt: DateTime.utc(2026),
    );
    expect(document.wordCount, 4);
    expect(document.toMap()['client_id'], 'local-document');
    expect(WritingDocument.fromMap(document.toMap()).content, document.content);
  });
}
