/// Feuille de style CSS embarquee dans les fichiers EPUB.
class EpubCss {
  const EpubCss._();

  /// Style par defaut, concu pour la lecture sur e-reader comme sur
  /// telephone.
  static const String content = '''
@charset "UTF-8";
html {
  font-size: 100%;
}
body {
  margin: 0 5%;
  font-family: Literata, Georgia, "Times New Roman", serif;
  line-height: 1.5;
  text-align: justify;
  hyphens: auto;
  widows: 2;
  orphans: 2;
}
h1, h2, h3 {
  font-family: Fraunces, Georgia, serif;
  line-height: 1.2;
  text-align: left;
  page-break-after: avoid;
  break-after: avoid;
}
h1 {
  font-size: 1.6em;
  margin: 1.2em 0 0.8em;
}
h2 {
  font-size: 1.3em;
  margin: 1.4em 0 0.6em;
}
h3 {
  font-size: 1.1em;
  margin: 1.2em 0 0.5em;
}
p {
  margin: 0 0 0.9em;
}
blockquote {
  margin: 1em 1.5em;
  font-style: italic;
  color: #444;
}
pre {
  font-family: "IBM Plex Mono", monospace;
  font-size: 0.85em;
  line-height: 1.4;
  white-space: pre-wrap;
  margin: 1em 0;
  padding: 0.6em;
  background: #f2f0eb;
  border-radius: 3px;
}
code {
  font-family: "IBM Plex Mono", monospace;
  font-size: 0.9em;
}
figure {
  margin: 1.2em 0;
  text-align: center;
}
figcaption {
  font-size: 0.85em;
  font-style: italic;
  margin-top: 0.4em;
}
aside[epub|type="footnote"] {
  font-size: 0.85em;
  border-top: 1px solid #ccc;
  margin-top: 1.5em;
  padding-top: 0.5em;
}
a[epub|type="noteref"] {
  text-decoration: none;
  vertical-align: super;
  font-size: 0.75em;
}
nav ol {
  list-style: none;
  padding-left: 0;
}
nav ol ol {
  padding-left: 1.2em;
}
nav li {
  margin: 0.35em 0;
}
''';
}
