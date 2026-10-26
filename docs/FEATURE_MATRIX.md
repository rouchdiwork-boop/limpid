# Limpid — Matrice fonctionnelle (analyse concurrentielle)

> Consolidation de **19 plateformes** de référence en une seule spécification.
> Chaque ligne indique l'origine de la fonctionnalité, ce qui permet de justifier
> les choix et de tracer la couverture.

**Légende** : ● natif & complet · ◐ présent mais partiel · ○ absent · ★ différenciateur Limpid

> **Ces marques décrivent la couverture visée**, c'est-à-dire la
> consolidation des dix-neuf plateformes de référence en une seule
> spécification. Elles ne disent pas ce qui est **livré** aujourd'hui : une
> ligne marquée ● peut être un travail started mais pas terminé. L'état
> réel, critère par critère, se lit dans
> [`ROADMAP.md`](./ROADMAP.md) — et l'audit qui l'établit est dans
> `docs/PRE-LIVRAISON.md` pour ce qui ne peut pas se vérifier depuis ce
> poste.

---

## 1. Cartographie des plateformes de référence

| Plateforme | Catégorie | Atout principal | Ce qu'on en prend |
|---|---|---|---|
| **Bookish** | Polonais, tout-en-un | Éditeur + structure + export EPUB/PDF | Modèle de données livre/chapitre, exports |
| **Pressbooks** | Auto-édition web | Publication web, ISBN, boutique | Vitrine publique, métadonnées, Connecteurs de vente |
| **Writebook** | OSS self-hosted | Markdown + git + plugins | Export Markdown, API/plugins, déploiement Railway |
| **Leanpub** | Vente d'ebooks | Coupons, bundles, free books, marketplace | Vente intégrée, code promo, bundling |
| **Shaxpir** | Auto-édition | Distribution multi-plateformes | Connecteurs KDP / Apple / Google / D2D |
| **Inkwell** | Structuré narratif | Personnages, lieux, chronologie | Story Bible, timeline |
| **Authorbot** | IA | Génération d'histoire à partir d'un concept | Générateur de synopsis + personnages + plan |
| **Scalar** | IA inline | IA dans le texte, multi-format | Actions IA en ligne |
| **Publiwrite** | IA | Worldbuilding + one-click book | Assistant IA multi-étapes |
| **Kutia** | IA + publication | Génération + KDP | Génération + distribution |
| **Built&Written** | Fiction | Fiches personnages, plan d'intrigue | Personnages, arcs, POV |
| **Papyrus Author** | Desktop | Trait de texte complet, styles, stats | Rendu WYSIWYG, styles, statistiques |
| **StoriesDen** | Fiction | Objectifs, beta-readers, gestion | Objectifs, stats, bêta-lecteurs |
| **BookScribi** | IA | Génération one-click + couverture | Génération + couverture IA |
| **CipherWrite** | Sécurité | Chiffrement, local-first | Chiffrement au repos, option E2EE |
| **Booova** | IA | Création rapide de livre | Templates "en 5 minutes" |
| **InkHack** | Minimal | Sans distraction | Mode focus, typographie éditoriale |
| **DraftMason** | Planification | Cartes de scènes, workflow | Cartes de scène, pipeline brouillon→révision→publié |
| **Anthra** | Gestion | Multi-roman, tableau de bord d'écriture | Vue multi-projets, tableaux de bord |

**Conclusion de l'analyse.** Aucun acteur ne couvre plus de 45 % de l'ensemble.
Les trois grands gaps : **IA contextuelle sérieuse** (RAG sur le manuscrit),
**temps réel hors-ligne**, et **vente/distribution intégrée**.

---

## 2. Fonctionnalités — Couverture complète

### 2.1 Écriture & éditeur

| # | Fonctionnalité | Origine | v1 | Notes |
|---|---|---|---|---|
| E1 | Éditeur rich text (Delta) — gras, italique, titres, listes, citation, code, note de bas de page | Bookish, Papyrus | ● | Styles, notes de bas de page |
| E2 | Menu slash `/` + palette de commandes | InkHack, Scalar | ● | |
| E3 | Mode focus (1 paragraphe) + mode Zen | InkHack, CipherWrite | ● | |
| E4 | Mode machine à écrire (scroll fixe) | Papyrus | ● | |
| E5 | Thème d'éditeur : police, taille, interligne, largeur de ligne | Papyrus, InkHack | ● | 6 presets + custom |
| E6 | Bloc de scène (unité atomique) + navigation clavier | Scrivener, Inkwell | ● | |
| E7 | Drag & drop de scènes avec index fractionnaire | Inkwell, Anthra | ● | |
| E8 | Lecture à voix haute (TTS) local | — | ◐ | Phase 2 |
| E9 | Correcteur orthographique multilingue | Papyrus | ◐ | Phase 2 (hunspell) |
| E10 | Find & replace + regex + stats de remplacement | Papyrus | ● | |
| E11 | Historique de versions + comparaison par bloc | Papyrus, Writebook | ● | |
| E12 | Import : DOCX, Markdown, TXT, RTF, EPUB, ODT | Bookish, Writebook | ● | |
| E13 | Export : EPUB3, PDF, DOCX, HTML, Markdown, ODT | Bookish, Papyrus, Writebook | ● | |
| E14 | Export PDF print-ready (marges, fond perdu, numérotation) | KDP | ◐ | Phase 2 |
| E15 | Autosave local + reprise après crash | CipherWrite, Writebook | ● | |
| E16 | Raccourcis clavier complets + palette de commandes globale | InkHack | ● | |
| E17 | Commentaires en marge, ancrés au texte | Papyrus, StoriesDen | ● | |
| E18 | Suivi des modifications (track changes) | Papyrus | ○ | Phase 3 |

### 2.2 Organisation & structure

| # | Fonctionnalité | Origine | v1 | Notes |
|---|---|---|---|---|
| O1 | Projet > Série > Tome > Chapitre > Scène | Inkwell, Anthra | ● | |
| O2 | Story Bible : personnages, lieux, objets, organisations | Inkwell, Built&Written | ● | |
| O3 | Fiches personnage détaillées (physique, voix, secrets, arcs) | Built&Written, Inkwell | ● | |
| O4 | Chronologie / timeline des événements | Inkwell, Anthra | ● | |
| O5 | Lignes narratives / arcs de plot (statut, résolution) | Built&Written | ● | |
| O6 | Suivi POV par scène | Built&Written | ● | |
| O7 | Étiquettes, collections, filtres intelligents | Bookish, Anthra | ● | |
| O8 | Champs personnalisés (métadonnées libres) | Anthra | ● | |
| O9 | Recherche plein texte multi-livres (local + FTS5) | Inkwell | ● | |
| O10 | Table des matières auto + mise à jour | Papyrus | ● | |
| O11 | Relation entre scènes (lien, inspiration) | InkHack | ◐ | Phase 2 |
| O12 | Modèle de "pipeline" : brouillon → révision → publié | DraftMason | ● | |

### 2.3 Progression & motivation

| # | Fonctionnalité | Origine | v1 | Notes |
|---|---|---|---|---|
| P1 | Objectif quotidien de mots | StoriesDen | ● | |
| P2 | Objectif par livre / par scène | StoriesDen | ● | |
| P3 | Série de jours consécutifs (streak) | StoriesDen | ● | |
| P4 | Historique d'écriture (heatmap calendrier) | Anthra, StoriesDen | ● | |
| P5 | Statistiques : mots, pages, temps de lecture, par scène | Papyrus, Anthra | ● | |
| P6 | Session d'écriture (minuteur, focus) | Papyrus | ● | |
| P7 | Suivi de progression de la série (arc/arc) | Anthra | ● | |

### 2.4 IA

| # | Fonctionnalité | Origine | v1 | Notes |
|---|---|---|---|---|
| A1 | Réécriture inline (étendre, raccourcir, simplifier, ton) | Scalar, Publiwrite | ● | |
| A2 | Continuation assistée | Scalar | ● | |
| A3 | Génération de plan à partir d'un concept | Authorbot, BookScribi | ● | |
| A4 | Génération de personnages + fiches | Authorbot, Publiwrite | ● | |
| A5 | Génération de monde / lieux | Publiwrite | ● | |
| A6 | Résumé de scène / chapitre | Scalar | ● | |
| A7 | "Interroge ton livre" (RAG sur le manuscrit) | ★ | ● | pgvector |
| A8 | Contrôle de cohérence (noms, chronologie, contradictions) | ★ | ● | |
| A9 | Analyse de style / profil de voix de l'auteur | ★ | ◐ | Phase 2 |
| A10 | Détection de clichés / mots répétés | Booova | ◐ | Phase 2 |
| A11 | Génération de couverture (image) | BookScribi, Kutia | ● | |
| A12 | Beat sheet (3 actes / Save the Cat) | DraftMason | ◐ | Phase 2 |
| A13 | Analyse de lisibilité (niveau Coleman-Liau) | ★ | ● | |
| A14 | Traduction assistée du manuscrit | ★ | ◐ | Phase 2 |

### 2.5 Collaboration

| # | Fonctionnalité | Origine | v1 | Notes |
|---|---|---|---|---|
| C1 | Édition temps réel (propagation < 300 ms) | ★ | ● | CRDT bloc |
| C2 | Présence : curseurs distants, avatars | ★ | ● | |
| C3 | Commentaires en marge + fils de discussion | Papyrus, StoriesDen | ● | |
| C4 | Rôles (propriétaire, co-auteur, bêta-lecteur, lecteur) | StoriesDen | ● | |
| C5 | Lien de partage en lecture (avec/sans commentaire) | Pressbooks | ● | |
| C6 | Publication d'extraits (chapitre gratuit) | Leanpub, Pressbooks | ● | |
| C7 | Invitations par email, expiration de lien | ★ | ● | |

### 2.6 Publication, vente & distribution

| # | Fonctionnalité | Origine | v1 | Notes |
|---|---|---|---|---|
| B1 | Page publique du livre (vitrine) | Pressbooks | ● | |
| B2 | Page auteur / catalogue | Pressbooks, Leanpub | ● | |
| B3 | Métadonnées : ISBN, BISAC, Contributeurs, droits | Shaxpir, Pressbooks | ● | |
| B4 | Générateur de couverture (maquette, dos, code-barres) | Shaxpir, Kutia | ● | |
| B5 | Vente directe (Stripe Checkout) | Leanpub | ● | |
| B6 | Code promo / free book / bundle | Leanpub | ● | |
| B7 | Partage des revenus (90/10 par défaut) | Leanpub | ● | |
| B8 | Connecteur Amazon KDP (upload + précommande) | Shaxpir, Kutia | ● | |
| B9 | Connecteur Leanpub (publication) | Leanpub | ◐ | Phase 2 |
| B10 | Connecteur Apple Books / Google Play | Shaxpir | ○ | Phase 3 |
| B11 | Draft2Digital / Smashwords | Shaxpir | ○ | Phase 3 |
| B12 | Génération de page de vente avec URL de téléchargement | Leanpub | ● | |
| B13 | Comptes rendus / avis sur la page publique | Pressbooks | ◐ | Phase 2 |

### 2.7 Plateforme & exploitation

| # | Fonctionnalité | Origine | v1 | Notes |
|---|---|---|---|---|
| T1 | Inscription magic link + OAuth (Google, Apple) | Writebook | ● | |
| T2 | 2FA TOTP | ★ | ● | |
| T3 | Appareils connectés + révocation de session | ★ | ● | |
| T4 | Hors-ligne complet (mobile + desktop + web PWA) | CipherWrite, Writebook | ★ | |
| T5 | Synchronisation multi-appareils | Writebook | ★ | CRDT bloc |
| T6 | Mode local / Ollama (Studio) | Publiwrite | ◐ | Phase 2 |
| T7 | Export complet des données (RGPD) | ★ | ● | |
| T8 | Suppression de compte + purge | ★ | ● | |
| T9 | API publique + webhooks | Writebook | ● | Studio |
| T10 | Back-office admin (users, plans, feature flags) | ★ | ● | |
| T11 | Rôles d'équipe + sièges | ★ | ● | Studio |
| T12 | Statistiques d'usage (D) | Anthra | ◐ | Phase 2 |

---

## 3. Couverture chiffrée

| Domaine | Fonctionnalités v1 | Origines couvertes |
|---|---|---|
| Écriture | 15 | Bookish, Papyrus, InkHack, Writebook, CipherWrite, Scalar |
| Organisation | 10 | Inkwell, Anthra, Built&Written, Scrivener, DraftMason |
| Progression | 6 | StoriesDen, Anthra, Papyrus |
| IA | 11 | Authorbot, Scalar, Publiwrite, Kutia, BookScribi, Booova |
| Collaboration | 6 | StoriesDen, Papyrus, Pressbooks |
| Publication & vente | 10 | Pressbooks, Leanpub, Shaxpir, Kutia |
| Plateforme | 9 | Writebook, CipherWrite, ★ |

**Couverture des 19 plateformes de référence : 19/19**
**Fonctionnalités v1 : 67** (sur 105 identifiées dans l'analyse)

---

## 4. Différenciateurs (ce qu'aucune des 19 ne fait bien)

1. **Écriture hors-ligne totale avec synchronisation CRDT par bloc** — seul CipherWrite
   est local-first, mais sans collaboration ni multi-appareil ; seul Writebook
   synchronise, mais sans modèle hors-ligne ni collaboration temps réel.
2. **IA contextuelle sur le manuscrit entier** — pas seulement « réécrire ce paragraphe »
   mais « où est-ce que j'ai établi que X ne peut pas entrer dans la ville ? ».
3. **Du premier au dernier livre, un seul outil** — structure narrative + IA + export +
   vente + distribution. Les concurrents sont pointés sur un seul maillon.

---

## 5. Anti-objectifs (ce qu'on ne fera PAS)

- Pas de traitement de texte généraliste (Word/LibreOffice) — on ne remplace pas un ODT.
- Pas de réseau social d'auteurs (pas de feed, pas de likes).
- Pas de bibliothèque de lecture type Goodreads (au-delà de la page publique).
- Pas de fragmentation — un seul produit, pas de marketplace de templates payants.
