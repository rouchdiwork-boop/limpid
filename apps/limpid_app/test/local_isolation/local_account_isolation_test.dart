import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_core/limpid_core.dart';

import 'support.dart';

/// The wall between two accounts on the same device.
///
/// The local database is unique per device and outlives the session: the
/// data of an account must never be served to another, and must never leave
/// the device under the session of another.
void main() {
  late SharedDevice device;

  setUp(() async {
    device = await openSharedDevice();
  });

  tearDown(() async {
    await device.database.close();
  });

  group('deux comptes sur le même poste', () {
    test(
      'le compte B ne voit ni la bibliothèque ni la file du compte A',
      () async {
        await device.manuscripts.createProject(title: 'Les Heures de Cendre');
        await device.manuscripts.applyOperations(<SyncOp>[
          insertBlockOp(
            documentId: 'document-1',
            authorId: SignedInAccount.firstAccount,
          ),
        ]);

        // A se déconnecte en gardant ses données, B se connecte.
        device.account.accountId = SignedInAccount.secondAccount;

        expect(await device.manuscripts.listProjects(), isEmpty);
        expect(await device.pendingOperations(), isEmpty);
      },
    );

    test('le compte A retrouve ses données en revenant', () async {
      await device.manuscripts.createProject(title: 'Les Heures de Cendre');
      await device.manuscripts.applyOperations(<SyncOp>[
        insertBlockOp(
          documentId: 'document-1',
          authorId: SignedInAccount.firstAccount,
        ),
      ]);

      device.account.accountId = SignedInAccount.secondAccount;
      expect(await device.manuscripts.listProjects(), isEmpty);

      // A revient sur le poste.
      device.account.accountId = SignedInAccount.firstAccount;

      final List<Project> projects = await device.manuscripts.listProjects();
      expect(projects, hasLength(1));
      expect(projects.single.title, 'Les Heures de Cendre');
      expect(await device.pendingOperations(), hasLength(1));
    });

    test(
      'les opérations du compte A ne partent pas sous la session de B',
      () async {
        await device.manuscripts.createProject(title: 'Les Heures de Cendre');
        await device.manuscripts.applyOperations(<SyncOp>[
          insertBlockOp(
            documentId: 'document-1',
            authorId: SignedInAccount.firstAccount,
          ),
        ]);

        // B collabore sur le livre de A : la synchronisation de B parcourt
        // donc le document de A.
        device.account.accountId = SignedInAccount.secondAccount;
        await device.manuscripts.saveProject(
          projectOf(authorId: SignedInAccount.firstAccount),
        );

        await device.sync.synchronize();

        expect(device.transport.pushed, isEmpty);
      },
    );

    test(
      'les instantanés du compte A ne sont pas rendus au compte B',
      () async {
        await device.manuscripts.applyOperations(<SyncOp>[
          insertBlockOp(
            documentId: 'document-1',
            authorId: SignedInAccount.firstAccount,
          ),
        ]);
        final CrdtDocument written = await device.manuscripts.loadDocument(
          'document-1',
        );
        expect(written.blocks, hasLength(1));

        device.account.accountId = SignedInAccount.secondAccount;

        final CrdtDocument read = await device.manuscripts.loadDocument(
          'document-1',
        );
        expect(read.blocks, isEmpty);
      },
    );
  });

  group('les préférences', () {
    test('sont cloisonnées par compte', () async {
      await device.preferences.setDailyGoal(2500);

      device.account.accountId = SignedInAccount.secondAccount;
      expect(await device.preferences.dailyGoal(), 1500);

      device.account.accountId = SignedInAccount.firstAccount;
      expect(await device.preferences.dailyGoal(), 2500);
    });

    test(
      'la série d’écriture ne montre pas les jours de l’autre compte',
      () async {
        await device.manuscripts.createProject(title: 'Les Heures de Cendre');
        await device.manuscripts.saveChapter(chapterOf());
        await device.manuscripts.saveScene(sceneOf());
        await device.database.writingSessions.recordWriting(
          day: DateTime.now(),
          projectId: 'project-1',
          words: 120,
          minutes: 12,
          accountId: SignedInAccount.firstAccount,
        );

        expect(await device.preferences.writingStreak(), 1);

        device.account.accountId = SignedInAccount.secondAccount;
        expect(await device.preferences.writingStreak(), 0);
      },
    );
  });

  group('l’effacement', () {
    test('vide les données de tous les comptes', () async {
      await device.manuscripts.createProject(title: 'Les Heures de Cendre');
      await device.manuscripts.applyOperations(<SyncOp>[
        insertBlockOp(
          documentId: 'document-1',
          authorId: SignedInAccount.firstAccount,
        ),
      ]);
      await device.preferences.setDailyGoal(2500);
      await device.database.writingSessions.recordWriting(
        day: DateTime.now(),
        projectId: 'project-1',
        words: 120,
        minutes: 12,
        accountId: SignedInAccount.firstAccount,
      );

      device.account.accountId = SignedInAccount.secondAccount;
      await device.preferences.setDailyGoal(900);

      await device.database.wiper.wipe();

      device.account.accountId = SignedInAccount.firstAccount;
      expect(await device.manuscripts.listProjects(), isEmpty);
      expect(await device.pendingOperations(), isEmpty);
      expect(await device.preferences.dailyGoal(), 1500);
      expect(await device.preferences.writingStreak(), 0);

      device.account.accountId = SignedInAccount.secondAccount;
      expect(await device.preferences.dailyGoal(), 1500);
    });
  });
}
