# limpid_ai — passerelle IA multi-fournisseurs

Package Dart pur (aucune dépendance Flutter) qui abstrait l'accès aux modèles de
langage pour Limpid : **Anthropic Claude** (par défaut), **tout endpoint compatible
OpenAI** (OpenAI, Groq, Together, DeepSeek, LM Studio, Ollama via `/v1`) et
**Ollama en mode local**.

Il fournit : streaming SSE, gouvernance des coûts par requête et par jour,
assemblage de contexte depuis le manuscrit, RAG local et une hiérarchie d'erreurs
typée.

Implémente les décisions **D-08** (passerelle IA), **D-15** (plans et quotas) et
**D-11** (design system, sans dépendance) du journal `docs/DECISIONS.md`, et couvre
les fonctions **A1 à A14** de `docs/FEATURE_MATRIX.md`.

---

## Installation

```yaml
dependencies:
  limpid_ai:
    path: ../packages/limpid_ai
```

```bash
dart pub get
```

Dépendances : `http` (transport), `crypto` (embedder de référence hors-ligne).
Aucune dépendance Flutter, aucun SDK fournisseur.

---

## Brancher une fournisseur

Toutes les fournisseurs implémentent `LlmProvider` et se construisent de la même
façon : un client HTTP injectable, un magasin de clés et une URL de base.

```dart
import 'package:http/http.dart' as http;
import 'package:limpid_ai/limpid_ai.dart';

// La clé vient du serveur, jamais du dépôt.
final InMemoryCredentialStore credentials = InMemoryCredentialStore();
credentials.store(AiProviderKind.anthropic, 'clé-lu-depuis-le-gestionnaire');

final AnthropicProvider anthropic = AnthropicProvider(
  httpClient: http.Client(),
  credentialStore: credentials,
);

final OpenAiCompatibleProvider groq = OpenAiCompatibleProvider(
  httpClient: http.Client(),
  credentialStore: credentials,
  baseUrl: 'https://api.groq.com/openai/v1',
  scope: 'groq',
);

final OllamaProvider local = OllamaProvider(
  httpClient: http.Client(),
  credentialStore: credentials,
  baseUrl: 'http://localhost:11434',
);
```

Le client se compose avec un résolveur : la tâche choisit sa fournisseur
recommandée, l'appel peut la surcharge.

```dart
final AiClient client = AiClient.withProviders(<AiProviderKind, LlmProvider>{
  AiProviderKind.anthropic: anthropic,
  AiProviderKind.openaiCompatible: groq,
  AiProviderKind.ollama: local,
});
```

### Les quatre points d'entrée

```dart
// 1. Génération simple
final AiResponse reponse = await client.generate(
  AiPrompt.systemAndUser(system: 'Tu es relecteur.', user: 'Relis ce passage.'),
  task: client.tasks.require(AiTaskKeys.summarize),
  tag: const AiCallTag(feature: 'summarize', userId: 'auteur-42'),
);

// 2. Streaming
await for (final AiChunk chunk in client.stream(
  AiPrompt.user('Continue ce passage.'),
  task: client.tasks.require(AiTaskKeys.continueText),
)) {
  if (chunk.isDone) {
    print(chunk.usage?.totalTokens);
  } else {
    print(chunk.text);
  }
}

// 3. Réécriture inline (A1)
await client.inline(const AiInlineRequest(
  action: AiInlineAction.changeTone,
  text: 'Il dit bonjour.',
  tone: 'plus distant',
));

// 4. Interrogation du manuscrit (A7)
await client.query(const AiQueryRequest(question: 'Pourquoi Mara part-elle ?'));
```

### Bascule de modèle

Trois paliers par défaut, surchargeables à chaque appel :

| Palier | Anthropic | Compatible OpenAI | Ollama |
|---|---|---|---|
| `AiModelTier.quality` | `claude-opus-5-5` | `gpt-4o` | `llama3.1` |
| `AiModelTier.balanced` | `claude-sonnet-5-5` | `gpt-4o-mini` | `llama3.1` |
| `AiModelTier.fast` | `claude-haiku-5-5` | `gpt-4o-mini` | `qwen2.5` |

```dart
// Surcharge ponctuelle
await client.generate(
  AiPrompt.user('...'),
  task: client.tasks.require(AiTaskKeys.summarize),
  options: const AiRequestOptions(model: 'claude-haiku-5-5', maxTokens: 512),
);

// Bascule de fournisseur
await client.generate(
  AiPrompt.user('...'),
  provider: AiProviderKind.ollama,
  scope: 'local',
);
```

> Les identifiants de modèle sont ceux des fournisseurs visés : ils doivent
> correspondre au catalogue en vigueur. Les modèles à raisonnement n'acceptant
> plus le paramètre `temperature`, passez `AiRequestOptions(omitTemperature: true)`.

---

## Les quatorze tâches

Coût estimé pour une exécution typique, selon la grille par défaut
(`AiPricing`) : `claude-opus-5-5` 15 $ / 75 $ par million de tokens,
`claude-sonnet-5-5` 3 $ / 15 $, `claude-haiku-5-5` 0,80 $ / 4 $.

| Clé | Fonction (A) | Modèle recommandé | Tokens in/out | Coût estimé | Catégorie |
|---|---|---|---|---|---|
| `rewrite_inline` | Réécriture inline (A1) | `claude-sonnet-5-5` | 900 / 600 | ≈ 0,012 $ | standard |
| `continue_text` | Continuation assistée (A2) | `claude-sonnet-5-5` | 1 400 / 900 | ≈ 0,018 $ | standard |
| `generate_outline` | Génération de plan (A3) | `claude-opus-5-5` | 1 200 / 2 600 | ≈ 0,213 $ | premium |
| `generate_characters` | Personnages + fiches (A4) | `claude-opus-5-5` | 1 200 / 2 600 | ≈ 0,213 $ | premium |
| `generate_world` | Monde et lieux (A5) | `claude-opus-5-5` | 1 200 / 2 600 | ≈ 0,213 $ | premium |
| `summarize` | Résumé scène / chapitre (A6) | `claude-haiku-5-5` | 4 000 / 700 | ≈ 0,006 $ | cheap |
| `query_book` | Interroge ton livre (A7) | `claude-sonnet-5-5` | 6 000 / 1 000 | ≈ 0,033 $ | standard |
| `check_consistency` | Contrôle de cohérence (A8) | `claude-sonnet-5-5` | 8 000 / 1 300 | ≈ 0,044 $ | standard |
| `analyze_style` | Profil de voix (A9) | `claude-sonnet-5-5` | 6 000 / 1 300 | ≈ 0,038 $ | standard |
| `detect_cliches` | Clichés et répétitions (A10) | `claude-haiku-5-5` | 5 000 / 1 000 | ≈ 0,008 $ | cheap |
| `generate_cover` | Couverture (A11) | `claude-sonnet-5-5` | 700 / 800 | ≈ 0,014 $ | standard |
| `generate_beat_sheet` | Beat sheet (A12) | `claude-sonnet-5-5` | 1 500 / 1 600 | ≈ 0,029 $ | standard |
| `analyze_readability` | Lisibilité (A13) | `claude-haiku-5-5` | 5 000 / 800 | ≈ 0,007 $ | cheap |
| `translate_text` | Traduction (A14) | `claude-sonnet-5-5` | 3 000 / 2 200 | ≈ 0,042 $ | standard |

Les tarifs sont des **estimations par défaut** : alignez-les sur la grille en
vigueur. Un modèle absent de la table est compté à 0 $ (mode local).

Les modèles de prompt sont en français, avec des garde-fous explicites (voix de
l'auteur, interdiction d'inventer, format de sortie). Ils sont regroupés par
domaine dans `lib/src/tasks/` et accessibles via `PromptTemplates`.

---

## Gouvernance des coûts

`BudgetGuard` applique deux plafonds et s'appuie sur un `UsageMeter` injecté par
l'API (base de données + Redis en production) :

```dart
final BudgetGuard guard = BudgetGuard(
  meter: monCompteur,                 // implémentation injectée par l'API
  maxTokensPerRequest: 8000,          // par appel
  maxTokensPerDay: 200000,            // par jour et par auteur
  maxCostPerDayUsd: 2.0,              // par jour et par auteur
);
```

- Un appel qui dépasse un plafond lève `AiBudgetExceeded` **avant** d'interroger
  la fournisseur.
- La consommation réelle est enregistrée après l'appel, y compris en fin de flux
  interrompu.
- Chaque appel est étiqueté (`AiCallTag` : fonctionnalité, utilisateur,
  fournisseur, tâche) pour l'audit et le quota du plan (D-15).

---

## Construction du contexte

`ContextBuilder` assemble le manuscrit dans une fenêtre de tokens, par ordre de
priorité décroissante :

1. **scène courante** ;
2. **chapitre** courant, puis chapitres voisins (triés par distance) ;
3. **bible** (personnages, lieux, chronologie) ;
4. **notes globales**.

Quand la fenêtre est saturée, les chapitres lointains sont écartés ; un bloc trop
grand est tronqué plutôt que perdu. L'assemblage rend compte de ce qu'il a inclus
et de ce qu'il a écarté.

```dart
final BuiltContext contexte = const ContextBuilder().build(
  monManuscrit,
  tokenWindow: 12000,
);
contexte.text;      // à injecter dans le prompt
contexte.included;  // blocs retenus
contexte.dropped;   // blocs écartés
```

Le nombre de tokens est estimé (4 caractères par token par défaut) ; injectez un
`TokenEstimator` plus précis si vous en disposez.

## RAG local

`RagIndex` est l'interface d'indexation ; `InMemoryVectorIndex` en est
l'implémentation de référence (similarité cosinus, en mémoire).
`HashingEmbeddingProvider` fournit un embedder déterministe et hors-ligne pour le
mode local et les tests.

**L'implémentation de production (pgvector) est fournie par l'API**, pas par ce
package.

---

## Confidentialité et mode local (D-08)

- Par défaut, **aucun texte d'auteur n'est envoyé à une fournisseur tiers sans
  consentement explicite** : ce choix appartient à l'API, qui décide du
  fournisseur (et l'enregistre dans le journal d'audit).
- Le mode **local only** utilise `OllamaProvider` : le texte ne quitte jamais la
  machine, le coût estimé est nul et aucun appel réseau tiers n'est effectué.
- Les erreurs ne renvoient jamais le contenu du manuscrit : `AiError` ne transporte
  qu'un code technique, un message utilisateur en français, un statut HTTP et un
  contexte de diagnostic sans secret.
- Les requêtes et réponses ne sont jamais journalisées par ce package.

## ⚠️ Gestion des clés — à lire avant toute intégration

- **Aucune clé d'API n'est stockée dans ce package.** Les clés sont résolues à
  l'exécution par un `AiCredentialStore`, dont l'implémentation réelle vit dans
  l'API.
- **Ne placez jamais une clé en dur** dans le code, dans un test, dans un fichier
  `.env` versionné ou dans un message de commit. Utilisez des variables
  d'environnement ou un gestionnaire de secrets (Railway, Supabase, Vault).
- **Ne loguez jamais une clé** : les erreurs transportent un contexte technique,
  jamais les en-têtes d'authentification.
- Le client Flutter **n'appelle jamais** une fournisseur directement : tous les
  appels passent par l'API, qui détient les clés et applique les quotas.
- `InMemoryCredentialStore` est fourni pour les tests et le démarrage d'un
  serveur : il ne persiste rien, il ne doit pas être utilisé en production.
- En cas de fuite, **révoquez la clé chez la fournisseur** avant toute autre
  action.

---

## Erreurs

| Classe | Code stable | Cas |
|---|---|---|
| `AiProviderError` | `ai_provider_error` | panne réseau, erreur HTTP générique |
| `AiProviderError` | `ai_auth_error` | clé absente, invalide ou expirée (401/403) |
| `AiProviderError` | `ai_missing_credentials` | aucune clé configurée pour ce fournisseur |
| `AiRateLimited` | `ai_rate_limited` | quota fournisseur atteint (429/529) |
| `AiTimeout` | `ai_timeout` | délai dépassé |
| `AiSafetyRefusal` | `ai_safety_refusal` | refus du modèle |
| `AiInvalidResponse` | `ai_invalid_response` | réponse illisible ou incomplète |
| `AiBudgetExceeded` | `ai_budget_exceeded` | plafond de tokens ou de coût atteint |

Les messages utilisateur sont en français ; les codes sont stables et traduisibles.

---

## Tests

```bash
cd packages/limpid_ai
dart pub get
dart analyze
dart test
```

Les tests n'effectuent **aucun appel réseau** : un client HTTP factice
(`test/helpers/fake_http_client.dart`) rejoue des réponses et des flux SSE/NDJSON
scriptés. Couverture : parsing SSE Anthropic et OpenAI, NDJSON Ollama, mapping
d'erreur 429 → `AiRateLimited`, plafond de budget, tri de similarité de
`InMemoryVectorIndex`, construction du contexte (écartement des chapitres
lointains), registre des quatorze tâches et façade `AiClient`.
