import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/local_manuscript_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_core/limpid_core.dart';

/// The demonstration mode on a shared device.
///
/// Nobody is signed in: the author of the demonstration is the local author,
/// and the scope of the local data follows it.
void main() {
  late AppDatabase database;

  setUp(() async {
    database = await AppDatabase.openWith(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('le scope de la base est celui de l’auteur local', () async {
    expect(database.account.accountId, kLocalAuthorId);
  });

  test('l’auteur local lit ses manuscrites', () async {
    final LocalManuscriptRepository manuscripts = LocalManuscriptRepository(
      database: database,
      author: const AuthorId(kLocalAuthorId),
    );
    await manuscripts.createProject(title: 'Le livre de démonstration');

    final List<Project> projects = await manuscripts.listProjects();

    expect(projects, hasLength(1));
    expect(projects.single.title, 'Le livre de démonstration');
  });
}
