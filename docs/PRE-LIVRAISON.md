# Liste de pré-livraison

Ce document recense **tout ce qui ne peut pas être vérifié depuis ce
poste** : les comptes des tiers, les clés d'API, le matériel, les
magasins d'applications et les validations juridiques.

## Le principe

Rien de cette liste **ne bloque** le développement. Chaque élément a été
construit avec un double, une porte de fonctionnalité ou une implémentation
de repli qui **dit** ce qui manque au lieu de faire semblant. La liste sert
de **filtre** avant la publication : on ne publie pas ce que l'on n'a pas
vérifié.

Une ligne est **close** quand la vérification a été faite **dans les
conditions réelles** — pas dans un test, pas avec un double.

| # | Élément | Ce qui bloque | Vérification | Bloque |
|---|---|---|---|---|
| 1 | Supabase Auth | un projet Supabase réel | inscription par lien magique, OAuth Google et Apple | la connexion |
| 2 | Stripe | un compte Stripe en mode bac à sable | un achat de bout en bout : page de vente (prix affiché), paiement sur la page du prestataire, réception du webhook, retour sur l'écran de retour, page de téléchargement | le paiement |
| 3 | Secret du webhook Stripe | la clé de signature | un webhook signé qui arrive, et un qui arrive **mal signé** et qui est refusé | la facturation |
| 4 | Cloudflare R2 | un seau et des identifiants | un export déposé, une URL signée qui expire | le stockage des exports |
| 5 | Anthropic | une clé d'API | une génération réelle, et le **consentement** enregistré avant le premier envoi de texte | l'IA |
| 6 | Amazon KDP | un compte développeur Amazon + une App SP-API | un dépôt réel, un refus réel lu et affiché | la publication Amazon |
| 7 | Redis | une instance | le cache, les clés d'idempotence, la file d'attente | la performance |
| 8 | Postgres | une base managée | les migrations appliquées, la réplication, la sauvegarde | la production |
| 9 | Android, iOS, macOS, Windows | les appareils et les certificats | les quatre faces rendues, l'écriture hors-ligne, la synchronisation | la publication |
| 10 | Les magasins d'applications | les comptes développeurs Apple et Google | la revue, la fiche, les captures | la distribution |
| 11 | Le droit | un juriste, un DPO | CGV, politique de confidentialité, registre des traitements, mention du DPO | la vente en France et en Europe |
| 12 | Le chiffrement de la base locale | la décision sur la clé | la base locale illisible sans la clé | l'option premium |
| 13 | La charge | une vraie audience | le budget de l'IA sous contrôle, la purge du cache d'export | l'exploitation |

## Les secrets, et où ils vont

Aucun de ces secrets ne vit dans le dépôt. Ils viennent de l'environnement
ou d'un gestionnaire de secrets, et ils sont **validés au démarrage** : une
clé absente ne fait pas tomber le serveur, elle désactive la
fonctionnalité et le dit.

| Variable | Sert à | Obligatoire |
|---|---|---|
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | l'authentification | oui |
| `SUPABASE_SERVICE_ROLE_KEY` | la purge du compte (D-19) | oui en production |
| `STRIPE_SECRET_KEY` | la commande et le portail de paiement | oui en production |
| `STRIPE_WEBHOOK_SECRET` | la signature du webhook entrant | oui en production |
| `ANTHROPIC_API_KEY` | le fournisseur d'IA | oui en production |
| `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET` | le stockage des exports | oui en production |
| `AMAZON_KDP_CLIENT_ID`, `AMAZON_KDP_CLIENT_SECRET`, `AMAZON_KDP_REFRESH_TOKEN` | le dépôt chez Amazon | non |
| `DATABASE_URL` | Postgres | selon le pilote |
| `REDIS_URL` | le cache | non |
| `CORS_ALLOWED_ORIGINS` | les origines autorisées | oui en production |
| `LIMPID_API_URL` | l'adresse de l'API dans l'application | non (un défaut local) |
| `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` | l'authentification dans l'application | oui |

## Ce qui a été traité par un double

Le tableau dit **ce qui a été vérifié en double** et **ce qui reste à
vérifier pour de vrai**. Une ligne de ce tableau n'est jamais close par un
test automatisé : un test prouve le contrat, pas le service tiers.

| Fonction | Le double | Ce qui reste à vérifier |
|---|---|---|
| L'IA | le fournisseur simulé, les tokens comptés | la latence réelle, le coût réel, le débit réel |
| Le paiement | le prestataire simulé, la signature vérifiée | l'achat complet, la TVA, le reçu, le remboursement |
| Le stockage | un stockage sur disque, les URL signées calculées | la durée de vie de l'URL, la politique de rétention |
| Amazon | un `http.Client` simulé, les adresses en constantes | le contrat réel de l'API, les quotas, le refus réel |
| L'authentification | Supabase simulé, le JWKS-local vérifié | l'inscription, la rotation du jeton, la révocation |
| La synchronisation | un serveur local, la convergence prouvée | la latence entre deux vrais clients |
| Le courriel | le journal du serveur, le lien rendu une fois à l'auteur | l'envoi reel, la|delivrance, le filtrage anti-spam |

## Ce que l'export RGPD exige du stockage objet

L'export des données personnelles est une **archive ZIP** : le serveur
écrit le fichier dans le stockage objet, sous le préfixe du compte, et
rend une **URL signée** valable quinze minutes. L'application télécharge
l'archive par cette URL, **sans** le jeton de session : l'URL porte sa
propre autorisation.

Sans `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` et
`R2_BUCKET`, `GET /v1/me/export` répond **503** : il n'y a pas d'archive
sans stockage. C'est la même exigence que l'export des livres, et c'est
la ligne 4 de ce tableau qui la ferme.

Trois points restent à vérifier en conditions réelles :

- la **durée de vie** de l'URL signée : quinze minutes sont suffisantes
  pour un téléchargement, mais il faut le confirmer avec le seau réel ;
- le **déchiffrement** de l'archive par l'auteur : elle contient le
  manuscrit, les réglages et l'historique du compte en clair, dans un
  ZIP que seul le mot de passe de l'archive protège — sur un poste
  partagé, c'est une faiblesse connue et assumée ;
- la **politique CORS du seau** : l'archive est téléchargée par le
  navigateur, depuis une autre origine que l'API. Le seau doit autoriser
  l'origine de l'application (`Access-Control-Allow-Origin`), sinon le
  navigateur refuse la reponse — et l'export passe pour une coupure
  reseau. C'est une configuration du seau, pas du code : sans elle, le
  telechargement ne fonctionne **que** sur les plateformes natives.

## Ce que les exports doivent prouver en conditions réelles

Les generateurs sont livres et testes, mais un test ne prouve pas ce qu'un
lecteur reel fait du fichier. Ces lignes ne se ferment que sur une machine
qui a les outils.

| Verification | Ce qu'elle exige | Ce qu'elle bloque |
|---|---|---|
| L'**EPUB** s'ouvre dans deux lecteurs de reference | `epubcheck` (l'outil de l'IDPF) et deux lecteurs reels (Calibre, Thorium, Adobe Digital Edition) | la vente du livre au format EPUB |
| Le **DOCX** et l'**ODT** s'ouvrent dans LibreOffice et Word | une suite bureautique reelle ; le test actuel ne verifie que la formation du XML | la vente du livre au format Word |
| Les **budgets d'export** sont tenus | un livre de 80 000 mots : EPUB en moins de 8 s, PDF reflowable en moins de 20 s, PDF print-ready en moins de 45 s | la promesse de l'ecran d'export |
| Le **PDF** rend **le meme** partout | le rendu sur trois plateformes, avec les polices embarquees | la vente du PDF |
| Les **polices** sont livrees | les seize fichiers OFL dans le depot, avec leur licence | la typographie de l'application et du PDF |
| La **couverture IA** est une image | une cle de fournisseur d'images ; le compteur de quotas compte aujourd'hui des **briefs** textuels | la promesse « cinq couvertures IA par mois » |
| La **recherche** tient son budget | un corpus d'un million de mots indexes : la reponse doit revenir en moins de 120 ms (ARCHITECTURE §9). Le test du depot mesure un ordre de grandeur sur 100 000 mots | la promesse « la recherche est instantanee » |

## Le point qui n'est pas fermé : le chiffrement de la base locale

D-05 annonce « SQLCipher en build desktop/mobile (option premium), volume
chiffré sur le web via IndexedDB + WebCrypto ». **Ce n'est pas
implémenté** : la base locale est un fichier SQLite en clair.

C'est cohérent tant que l'option premium n'est pas vendue : le contenu du
manuscrit est déjà chiffré par le transport (TLS 1.3) et le stockage
distant est chiffré côté fournisseur. Mais le jour où le premium existe,
cette ligne doit être close **avant** la vente, pas après.

La décision à prendre : quelle clé, et où elle vit ? Une clé par compte
(chiffrage par enveloppe, comme le D-19 le prévoit pour le contenu des
ouvrages) ou une clé par poste (protège contre un vol de matériel, pas
contre un compte volé) ?

## Comment on ferme une ligne

1. La clé ou le compte est mis à disposition dans l'environnement de la
   pré-livraison, **jamais** dans le dépôt.
2. Le scénario est rejoué **pour de vrai** : le scénario du tableau, pas
   un test.
3. Ce qui a été observé est écrit ici, avec la date.
4. La ligne est close, ou elle porte ce qui a empêché de la fermer.

La liste est mise à jour à chaque lot. Une ligne close n'est jamais
réouverte sans une raison écrite.
