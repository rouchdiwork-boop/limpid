# limpid_sync

Client de synchronisation CRDT de **Limpid** : il pousse et tire les
opérations du CRDT vers l'API, tient une file d'attente locale hors-ligne et
converge.

Dart pur : aucun import `package:flutter/*`, le package se teste avec
`dart test` sans device, sans réseau et sans base de données.

## Rôle dans l'architecture

```
limpid_core  →  aucune dépendance (Dart pur)
limpid_sync  →  limpid_core, http, web_socket_channel, drift, sqlite3
```

`limpid_sync` ne réimplémente **aucun** algorithme du CRDT : la
convergence, la fusion 3-way du texte et l'ordre last-writer-wins restent
dans `limpid_core` (D-04). Ce package ne fait que transporter, ordonnancer et
persister les opérations.

## Composants

| Fichier | Responsabilité |
|---|---|
| `lib/src/transport/sync_transport.dart` | Interface `SyncTransport`, `PushResult`, `TransportEvent` |
| `lib/src/transport/http_sync_transport.dart` | Transport REST (`POST /v1/projects/:id/ops`, `GET …?since=`) |
| `lib/src/transport/web_socket_sync_transport.dart` | Canal temps réel `WS /v1/sync` (délègue le push/pull au REST) |
| `lib/src/transport/op_codec.dart` | Encodage JSON des opérations (format `docs/ARCHITECTURE.md` §5.1) |
| `lib/src/queue/op_queue.dart` | File d'attente : état `pending`/`sent`/`failed`, backoff exponentiel + jitter |
| `lib/src/queue/memory_op_queue_store.dart` | Store mémoire (tests, applications sans persistance) |
| `lib/src/db/drift_op_queue_store.dart` | Store Drift (SQLite) de la file d'attente |
| `lib/src/db/drift_snapshot_store.dart` | Store Drift du snapshot local et du curseur |
| `lib/src/snapshot_store.dart` | Snapshot CRDT + curseur `since` |
| `lib/src/sync_client.dart` | Orchestrateur : `enqueue`, `sync`, `watch`, déduplication, état |
| `lib/src/network_status.dart` | `ConnectivityProbe` (ping de l'API par défaut) |
| `lib/src/conflict.dart` + `conflict_detector.dart` | Détection et présentation des divergences |

## Choix d'architecture

### Persistance : interface + Drift, pas de liaison Flutter

La file d'attente et les snapshots sontdefinitions derrière deux interfaces
(`OpQueueStore`, `SnapshotStore`). Deux implémentations sont fournies :

- **mémoire** (`InMemoryOpQueueStore`, `InMemorySnapshotStore`) — tests et
  usages sans persistance ;
- **Drift** (`DriftOpQueueStore`, `DriftSnapshotStore`) — SQLite local.

Drift est utilisé **sans `sqlite3_flutter_libs`** : le package reste en Dart
pur. **L'ouverture de la base est la responsabilité de l'application** : le
package ne manipule que l'exécuteur qu'on lui donne.

```dart
// Application Flutter
final database = SyncDatabase(
  NativeDatabase.createInBackground(file),
);
// Application Dart pure
final database = SyncDatabase(NativeDatabase.memory());
```

### Transport : REST pour le push/pull, WebSocket pour le temps réel

`HttpSyncTransport` et `WebSocketSyncTransport` implémentent la même
interface. Le second **délègue** le push et le pull au premier : une seule
implémentation de la logique REST, un seul point de vérité sur le format
des opérations.

Le `http.Client` et le `WebSocketChannel` sont **injectés**, ce qui rend les
tests totalement déterministes et sans réseau.

### Curseur `since`

Le curseur est un **curseur de livraison dense et monotone** : le serveur
renvoie un intervalle contigu du journal et le client l'avance du nombre
d'opérations reçues. C'est ce qui rend le pull sans perte quand plusieurs
répliques écrivent en même temps avec des horloges Lamport distinctes.

### Snapshot : le journal compacté, pas les blocs

`limpid_core` n'expose pas de sérialiseur pour `CrdtDocument` : le document
garde la forêt des versions de chaque bloc, les tombstones et l'ensemble des
opérations appliquées, état non reconstructible depuis les blocs publics
(la base de la fusion 3-way serait perdue). Le snapshot stocke donc le
**journal compacté des opérations** ; le document est restauré en le
rejouant, ce qui est déterministe. La compaction de `docs/ARCHITECTURE.md`
§5.4 pourra élaguer le journal sans changer la sémantique.

### Conflits : le client n'arbitre jamais

`ConflictDetector` compare les versions locales et distantes d'un même bloc et
publie un `ConflictReport` contenant **les deux versions** et la position
du bloc dans le document. L'application choisit ensuite avec
`ConflictResolver` : `keepLocal`, `keepRemote` ou `merge` (fusion 3-way de
`limpid_core`). C'est le comportement de l'écran « Hors-ligne &
synchronisation » de la maquette.

## Contrat hors-ligne

- `enqueue(op)` **n'échoue jamais** à cause du réseau : l'opération est
  persistée dans la file **avant** toute tentative d'envoi, puis le client
  tente de l'envoyer si le réseau est là.
- Quand l'API est injoignable, l'état passe à `SyncStatus.offline` et la
  file s'accumule. Les opérations échouées sont retentées avec un backoff
  exponentiel et un jitter.
- `sync(docId)` ne lève pas d'exception pour une panne de connectivité : il
  passe en `offline` et renvoie un rapport vide. Les autres erreurs
  (authentification, erreur serveur, conflit) ne sont **pas** avalées : elles
  sont publiées sur le flux d'événements, enregistrées dans l'état et
  relancées.
- La déduplication se fait par `(docId, lamport, authorId)`, la clé
  d'identité d'une opération dans `limpid_core`.

## Utilisation

```dart
final client = SyncClient(
  documentId: const DocumentId('scene-1'),
  authorId: const AuthorId('author-a'),
  transport: HttpSyncTransport(
    baseUrl: Uri.parse('https://api.limpid.app'),
    client: http.Client(),
    tokenProvider: () => session.accessToken(),
  ),
  queueStore: DriftOpQueueStore(database),
  snapshotStore: DriftSnapshotStore(database),
  connectivity: HttpConnectivityProbe(
    baseUrl: Uri.parse('https://api.limpid.app'),
    client: http.Client(),
  ),
);

client.watch('scene-1').listen((event) {
  switch (event) {
    case SyncLocalOpApplied(:final operation):
      render(operation);
    case SyncRemoteOpApplied(:final operation):
      render(operation);
    case SyncConflictDetected(:final reports):
      showConflictDialog(reports);
    case SyncStateChanged(:final state):
      showBadge(state.pendingCount, state.status);
    default:
      break;
  }
});

await client.enqueue(operation);   // écrit, puis envoie si en ligne
await client.sync('scene-1');      // envoie la file, puis tire le distant
```

## Collision de nom avec `limpid_core`

`limpid_core` déclare aussi un `SyncTransport`, avec un contrat beaucoup plus
étroit (il ne connaît ni la file, ni le curseur, ni le canal temps réel).
Le transport de `limpid_sync` est celui que l'application doit utiliser.
Quand les deux paquets sont importés, masquez celui de `limpid_core` :

```dart
import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';
```

## Développement

```bash
dart pub get
dart analyze                                    # 0 erreur, 0 warning, 0 info
dart test                                       # 100 % vert
dart format --set-exit-if-changed .             # 0 fichier modifié
dart run build_runner build                     # regénère sync_database.g.dart
```

Le test le plus important est `test/client/convergence_test.dart` : deux
répliques écrivent hors-ligne en parallèle, un faux serveur relaie les
opérations dans un ordre aléatoire, et les deux clients doivent finir avec un
`CrdtDocument` strictement identique.
