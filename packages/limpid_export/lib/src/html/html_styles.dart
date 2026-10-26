/// Feuille de style de l'ebook HTML.
///
/// Le style est inline (dans la page) afin que le fichier produit soit
/// autonome et lisible hors-ligne, sur telephone comme sur ordinateur.
class HtmlStyles {
  const HtmlStyles._();

  /// Style de l'ebook.
  static const String ebook = '''
:root {
  --encre: #1c1a17;
  --papier: #faf8f4;
  --accent: #8a5a2b;
  --muted: #6b6459;
  --mesure: 34rem;
}
@media (prefers-color-scheme: dark) {
  :root {
    --encre: #ece7df;
    --papier: #14110e;
    --muted: #a49b8c;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0;
  padding: 2.5rem 1.25rem 4rem;
  background: var(--papier);
  color: var(--encre);
  font-family: Georgia, "Times New Roman", serif;
  font-size: 1.0625rem;
  line-height: 1.65;
}
.book { max-width: var(--mesure); margin: 0 auto; }
.book-header { text-align: center; margin-bottom: 3.5rem; }
.book-title { font-size: 2.25rem; line-height: 1.15; margin: 0 0 .5rem; }
.book-subtitle { font-size: 1.25rem; color: var(--muted); margin: 0 0 1rem; }
.book-authors { font-size: 1rem; letter-spacing: .08em; text-transform: uppercase; color: var(--muted); margin: 0; }
.chapter { margin-bottom: 3rem; }
.chapter-title { font-size: 1.75rem; line-height: 1.2; margin: 2.5rem 0 1.25rem; }
h3 { font-size: 1.3rem; margin: 2rem 0 .75rem; }
h4 { font-size: 1.1rem; margin: 1.5rem 0 .5rem; }
p { margin: 0 0 1.1rem; text-align: justify; hyphens: auto; }
blockquote {
  margin: 1.5rem 0;
  padding-left: 1.25rem;
  border-left: 3px solid var(--accent);
  font-style: italic;
  color: var(--muted);
}
pre {
  background: rgba(128, 128, 128, .12);
  padding: 1rem;
  overflow-x: auto;
  font-family: "IBM Plex Mono", ui-monospace, monospace;
  font-size: .9rem;
  line-height: 1.5;
  border-radius: 4px;
}
code { font-family: "IBM Plex Mono", ui-monospace, monospace; font-size: .92em; }
figure { margin: 2rem 0; text-align: center; }
figure img { max-width: 100%; height: auto; }
figcaption { font-size: .875rem; color: var(--muted); margin-top: .5rem; }
ul, ol { margin: 0 0 1.1rem; padding-left: 1.5rem; }
li { margin-bottom: .4rem; }
.footnotes { margin-top: 3rem; font-size: .9rem; color: var(--muted); }
.footnotes h2 { font-size: 1rem; text-transform: uppercase; letter-spacing: .06em; }
.footnote-ref { font-size: .75em; vertical-align: super; text-decoration: none; }
.page-break { break-after: page; }
''';

  /// Style de la page de vente.
  static const String salesPage = '''
:root {
  --encre: #1c1a17;
  --papier: #faf8f4;
  --accent: #8a5a2b;
  --muted: #6b6459;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  padding: 3rem 1.25rem 5rem;
  background: var(--papier);
  color: var(--encre);
  font-family: Georgia, "Times New Roman", serif;
  line-height: 1.65;
}
.page { max-width: 42rem; margin: 0 auto; }
.hero { text-align: center; margin-bottom: 3rem; }
.cover { max-width: 18rem; height: auto; border-radius: 4px; box-shadow: 0 12px 32px rgba(0,0,0,.18); }
.title { font-size: 2.5rem; line-height: 1.1; margin: 1.5rem 0 .5rem; }
.subtitle { font-size: 1.25rem; color: var(--muted); margin: 0 0 1rem; }
.authors { text-transform: uppercase; letter-spacing: .08em; font-size: .95rem; color: var(--muted); margin: 0 0 2rem; }
.description { font-size: 1.05rem; }
.meta { color: var(--muted); font-size: .9rem; margin-top: 2.5rem; }
.meta dl { display: grid; grid-template-columns: max-content 1fr; gap: .35rem 1rem; }
.meta dt { font-weight: 700; }
.meta dd { margin: 0; }
''';
}
