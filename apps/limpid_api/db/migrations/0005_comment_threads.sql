-- Fils de discussion ancres sur les marques du CRDT (D-16, ARCHITECTURE.md §8).
-- L'ancre reste une marque du document, qui ne confond jamais avec le texte ;
-- la conversation, son auteur et sa resolution sont stockees ici.
CREATE TABLE IF NOT EXISTS comment_threads (
  id          TEXT PRIMARY KEY,
  project_id  TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
  mark_id     TEXT NOT NULL,
  excerpt     TEXT NOT NULL DEFAULT '',
  is_resolved BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS comment_threads_project_idx
  ON comment_threads (project_id, created_at, id);

CREATE TABLE IF NOT EXISTS comments (
  id          TEXT PRIMARY KEY,
  thread_id   TEXT NOT NULL REFERENCES comment_threads (id) ON DELETE CASCADE,
  author_id   TEXT NOT NULL,
  body        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  edited_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS comments_thread_idx
  ON comments (thread_id, created_at, id);
