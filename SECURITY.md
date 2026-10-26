# Sécurité

Limpid traite des manuscrits, des comptes d'auteur et des moyens de paiement.
La sécurité est traitée comme une exigence de conception, pas comme une
correction afterthought. Les décisions structurantes sont consignées dans
[`docs/DECISIONS.md`](docs/DECISIONS.md) (D-19) et
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Signaler une faille

**Ne publiez pas une faille dans une issue publique.**

| Étape | Action |
|---|---|
| 1 | Ouvrir un fil privé : **Security → Report a vulnerability** dans l'onglet Security de la page du dépôt |
| 2 | Décrire la faille : ce qui est en cause, les étapes de reproduction, l'impact |
| 3 | Attendre l'accusé de réception de l'équipe |

Nous accusons réception sous 72 heures et nous tenons informés de l'avancement.
La fenêtre de correction annoncée avant publication est d'au moins 90 jours
pour une faille critique.

Une faille déjà publiée est traitée comme une urgence : la bragance compte
comme une bonne intention, la divulgation publique n'est pas nécessaire.

---

## Périmètre

| Élément | Politique |
|---|---|
| Application web, API, synchronisation, exports | Oui |
| Client mobile et desktop | Oui |
| Client de synchronisation (`limpid_sync`) | Oui |
| Passerelle IA (`limpid_ai`) | Oui |
| Dépendances | Signalement via le mécanisme ci-dessus, avec la version affectée |

---

## Modèle de menace et contrôles

| Contrôle | Décision |
|---|---|
| Mots de passe | Argon2id via Supabase Auth, aucun hash maison |
| Sessions | JWT court (15 min) + refresh rotatif, révocation serveur |
| 2FA | TOTP obligatoire pour les plans Pro et Studio |
| Données au repos | TLS 1.3 en transit ; SQLCipher local ; R2 chiffré (SSE) |
| E2EE | Option premium : chiffrement client du contenu des ouvrages |
| Secrets | Variables d'environnement et gestionnaire, **jamais** dans le dépôt |
| Isolation | Row-Level Security sur toutes les tables multi-utilisateur |
| Journal d'audit | Export, partage, suppression, changement de plan |
| Export utilisateur | ZIP complet (manuscrits, assets, réglages) — RGPD |
| Suppression | Soft delete 30 jours, puis purge définitive et exclusion des index IA |

## Règles pour les contributeurs

Avant toute pull request :

- [ ] Aucun secret dans le dépôt (clés, jetons, mots de passe, certificats)
- [ ] Toutes les entrées utilisateur sont validées avant traitement
- [ ] Les requêtes SQL sont paramétrées, jamais concaténées
- [ ] Aucun HTML non assaini dans le code web
- [ ] Les messages d'erreur ne divulguent ni stack trace, ni requête, ni secret
- [ ] Les secrets de la CI ne sont lus que par le job qui en a besoin
- [ ] Les données sensibles ne sont jamais journalisées

Les dépendances sont déclarées avec leur justification dans la pull request
([`CONTRIBUTING.md`](CONTRIBUTING.md)).

## Ce que fait la CI

- **Analyse statique** sur chaque push et chaque pull request
  (`.github/workflows/ci.yml`).
- **CodeQL** pour l'analyse de sécurité en continu
  (`.github/workflows/codeql.yml`). Dart n'étant pas encore un langage pris en
  charge par CodeQL, ce job est câblé mais non bloquant.
- **Permissions minimales** : la CI n'a que `contents: read`.
- **Aucune branche de développement** n'est protégée par un secret : les
  secrets de déploiement ne sont accessibles qu'aux flux de `main` et de tag.

## Divulgation responsable

- Tester sur une installation qui vous appartient, ou avec l'accord écrit du
  propriétaire.
- Ne pas accéder aux données d'un autre utilisateur, même si l'accès est
  techniquement possible.
- Ne pas dégrader le service (pas de charge automatisée, pas de flood).
- Ne pas utiliser les vulnérabilités pour du spam, de la fraude ou de la
  diffusion de contenu.
- Donnez un délai raisonnable avant la divulgation publique.

## Remerciements

Les signalements de qualité sont remerciés publiquement, avec votre accord, dans
les notes de version. Nous ne publions pas de programme de bug bounty à ce
jour.
