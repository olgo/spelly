-- =========================================================
--  Spelly – Datenmodell (PostgreSQL / Supabase)
--  Asynchroner 2-Spieler-Modus, server-autoritativ
-- =========================================================

-- ---------- Typen ----------

create type game_status as enum ('waiting', 'active', 'finished', 'abandoned');
create type move_kind   as enum ('play', 'pass', 'exchange', 'resign', 'timeout');

-- ---------- Profile ----------
-- Ergänzt auth.users um spielbezogene Daten.

create table profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 2 and 24),
  elo          int  not null default 1200,
  created_at   timestamptz not null default now()
);

-- ---------- Partien ----------
-- Alles, was BEIDE Spieler sehen dürfen.
-- Beutel und Rack liegen bewusst NICHT hier (siehe unten).

create table games (
  id                  uuid primary key default gen_random_uuid(),
  status              game_status not null default 'waiting',

  -- Brett: 225 Einträge, null = leer, sonst {"l":"A","b":false}
  -- b = true bedeutet, der Stein ist ein eingesetzter Blanko.
  board               jsonb not null default '[]'::jsonb,

  current_seat        smallint not null default 0,
  turn_number         int      not null default 0,
  consecutive_passes  smallint not null default 0,
  tiles_left          smallint not null default 102,   -- nur die ANZAHL, nicht der Inhalt

  dict_version        text not null,                   -- z.B. 'de-2026.1'
  winner_id           uuid references profiles(id),

  created_at          timestamptz not null default now(),
  last_move_at        timestamptz not null default now(),
  deadline_at         timestamptz                      -- für Auto-Resign nach Inaktivität
);

create index on games (status, deadline_at);

-- ---------- Teilnahme ----------
-- Öffentlich sichtbare Spielerdaten einer Partie: Sitz und Punktestand.

create table game_players (
  game_id    uuid     not null references games(id) on delete cascade,
  player_id  uuid     not null references profiles(id),
  seat       smallint not null check (seat in (0, 1)),
  score      int      not null default 0,
  joined_at  timestamptz not null default now(),

  primary key (game_id, player_id),
  unique (game_id, seat)
);

create index on game_players (player_id);

-- ---------- Geheime Spielerdaten ----------
-- Eigene Tabelle, weil RLS nur ZEILEN filtern kann, keine Spalten.
-- Läge das Rack in game_players, müsste man entweder die ganze Zeile
-- des Gegners verstecken (dann wäre sein Punktestand weg) oder das
-- Rack mitliefern. Deshalb die Trennung.

create table racks (
  game_id    uuid not null references games(id) on delete cascade,
  player_id  uuid not null references profiles(id),
  tiles      text[] not null default '{}',   -- z.B. {'A','E','R','?','N','T','S'}, '?' = Blanko
  primary key (game_id, player_id)
);

-- ---------- Beutel ----------
-- Darf für NIEMANDEN lesbar sein, auch nicht für die Spieler selbst.
-- Nur die service_role (Edge Function) greift darauf zu.

create table game_secrets (
  game_id  uuid primary key references games(id) on delete cascade,
  bag      text[] not null,
  rng_seed bigint not null
);

-- ---------- Züge ----------
-- Vollständiges Protokoll. Erlaubt Replay, Statistiken und Streitfälle.

create table moves (
  id          bigserial primary key,
  game_id     uuid     not null references games(id) on delete cascade,
  seq         int      not null,
  player_id   uuid     not null references profiles(id),
  kind        move_kind not null,

  -- [{"r":7,"c":7,"l":"H","b":false}, ...]
  placements  jsonb not null default '[]'::jsonb,
  -- [{"w":"HAUS","s":14}, ...]  alle in diesem Zug gebildeten Wörter
  words       jsonb not null default '[]'::jsonb,
  score       int   not null default 0,

  created_at  timestamptz not null default now(),

  unique (game_id, seq)
);

create index on moves (game_id, seq);

-- ---------- Push-Tokens ----------

create table devices (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  fcm_token   text not null unique,
  platform    text not null check (platform in ('ios', 'android')),
  updated_at  timestamptz not null default now()
);

-- ---------- Wort-Meldungen ----------
-- Feedback-Kanal, um die Wortliste über die Zeit nachzuschärfen.

create table word_reports (
  id           bigserial primary key,
  word         text not null,
  reporter_id  uuid references profiles(id),
  game_id      uuid references games(id) on delete set null,
  reason       text not null check (reason in ('missing', 'invalid')),
  dict_version text not null,
  resolved     boolean not null default false,
  created_at   timestamptz not null default now()
);

create index on word_reports (word, resolved);

-- =========================================================
--  Row Level Security
-- =========================================================

-- Hilfsfunktion: bin ich Teilnehmer dieser Partie?
-- SECURITY DEFINER umgeht RLS innerhalb der Funktion – sonst würde sich
-- die Policy auf game_players selbst rekursiv aufrufen.

create or replace function is_participant(g uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from game_players
    where game_id = g and player_id = auth.uid()
  );
$$;

alter table profiles      enable row level security;
alter table games         enable row level security;
alter table game_players  enable row level security;
alter table racks         enable row level security;
alter table game_secrets  enable row level security;
alter table moves         enable row level security;
alter table devices       enable row level security;
alter table word_reports  enable row level security;

-- Profile: alle lesbar (Anzeigename im Spiel), nur selbst änderbar.
create policy profiles_read   on profiles for select using (true);
create policy profiles_update on profiles for update using (id = auth.uid());

-- Partien: nur eigene.
create policy games_read on games for select
  using (is_participant(id));

-- Teilnahme + Punktestände: sichtbar, wenn man selbst in der Partie ist.
create policy game_players_read on game_players for select
  using (is_participant(game_id));

-- Rack: ausschliesslich das eigene.
create policy racks_read on racks for select
  using (player_id = auth.uid());

-- Züge: für beide Teilnehmer lesbar.
create policy moves_read on moves for select
  using (is_participant(game_id));

-- Geräte: nur eigene, volles CRUD.
create policy devices_all on devices for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Meldungen: anlegen ja, lesen nein.
create policy word_reports_insert on word_reports for insert
  with check (reporter_id = auth.uid());

-- game_secrets: KEINE Policy. Bei aktivem RLS ohne Policy sieht
-- kein normaler Client irgendetwas. Nur service_role kommt heran.

-- Kein INSERT/UPDATE für Clients auf games, game_players, racks, moves:
-- jeder Zug läuft über eine Edge Function mit service_role, die Legalität,
-- Wörter und Punkte selbst berechnet.

-- =========================================================
--  Trigger: Push-Benachrichtigung nach jedem Zug
-- =========================================================

create or replace function notify_opponent()
returns trigger
language plpgsql
security definer
as $$
begin
  perform net.http_post(
    url     := current_setting('app.push_function_url'),
    body    := jsonb_build_object('game_id', new.game_id, 'move_seq', new.seq)
  );
  return new;
end;
$$;

create trigger moves_notify
  after insert on moves
  for each row execute function notify_opponent();
