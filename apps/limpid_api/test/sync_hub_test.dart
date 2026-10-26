import 'package:limpid_api/limpid_api.dart';
import 'package:test/test.dart';

void main() {
  group('relais de synchronisation', () {
    test('sépare les documents homonymes de deux projets', () async {
      final SyncHub hub = SyncHub();
      addTearDown(hub.close);

      final SyncSubscription first = hub.join(
        projectId: 'projet-1',
        docId: 'doc-1',
        userId: 'user-1',
      );
      final SyncSubscription second = hub.join(
        projectId: 'projet-2',
        docId: 'doc-1',
        userId: 'user-2',
      );

      final List<Map<String, Object?>> receivedByFirst =
          <Map<String, Object?>>[];
      final List<Map<String, Object?>> receivedBySecond =
          <Map<String, Object?>>[];
      first.frames.listen(receivedByFirst.add);
      second.frames.listen(receivedBySecond.add);

      hub.broadcast('projet-1', 'doc-1', <String, Object?>{'type': 'op'});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(receivedByFirst, hasLength(1));
      expect(receivedBySecond, isEmpty);
    });

    test('compte les abonnés de chaque salle', () {
      final SyncHub hub = SyncHub();
      addTearDown(hub.close);

      hub.join(projectId: 'projet-1', docId: 'doc-1', userId: 'user-1');
      hub.join(projectId: 'projet-1', docId: 'doc-1', userId: 'user-2');
      hub.join(projectId: 'projet-2', docId: 'doc-1', userId: 'user-3');

      expect(hub.subscriberCount('projet-1', 'doc-1'), 2);
      expect(hub.subscriberCount('projet-2', 'doc-1'), 1);
      expect(hub.subscriberCount('projet-2', 'doc-2'), 0);
    });

    test('n\'envoie pas l\'opération à celui qui l\'a produite', () async {
      final SyncHub hub = SyncHub();
      addTearDown(hub.close);

      final SyncSubscription author = hub.join(
        projectId: 'projet-1',
        docId: 'doc-1',
        userId: 'user-1',
      );
      final SyncSubscription other = hub.join(
        projectId: 'projet-1',
        docId: 'doc-1',
        userId: 'user-2',
      );

      final List<Map<String, Object?>> receivedByAuthor =
          <Map<String, Object?>>[];
      final List<Map<String, Object?>> receivedByOther =
          <Map<String, Object?>>[];
      author.frames.listen(receivedByAuthor.add);
      other.frames.listen(receivedByOther.add);

      hub.broadcast('projet-1', 'doc-1', <String, Object?>{
        'type': 'op',
      }, except: author);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(receivedByAuthor, isEmpty);
      expect(receivedByOther, hasLength(1));
    });
  });
}
