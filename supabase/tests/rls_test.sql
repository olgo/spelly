-- pgTAP: prüft, dass die Policies genau das preisgeben, was sie sollen.
--
--   supabase test db
--
-- Das ist die wichtigste Testdatei im Projekt. Ein Loch in der racks-Policy
-- merkt man im Betrieb nicht – der Client zeigt das gegnerische Rack ja nicht
-- an. Auffallen würde es erst, wenn jemand die API direkt anspricht und
-- mitliest, welche Steine der Gegner hält.

begin;

create extension if not exists pgtap with schema extensions;

select plan(18);

-- ---------------------------------------------------------------
--  Testdaten
-- ---------------------------------------------------------------

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'anna@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'bert@example.test'),
  ('33333333-3333-3333-3333-333333333333', 'clara@example.test');

insert into profiles (id, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'Anna'),
  ('22222222-2222-2222-2222-222222222222', 'Bert'),
  ('33333333-3333-3333-3333-333333333333', 'Clara');

insert into games (id, status, board, current_seat, tiles_left, dict_version)
values (
  'aaaaaaaa-0000-0000-0000-000000000001',
  'active',
  (select jsonb_agg(null::jsonb) from generate_series(1, 225)),
  0, 88, 'de-test'
);

insert into game_players (game_id, player_id, seat, score) values
  ('aaaaaaaa-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 0, 24),
  ('aaaaaaaa-0000-0000-0000-000000000001',
   '22222222-2222-2222-2222-222222222222', 1, 31);

insert into racks (game_id, player_id, tiles) values
  ('aaaaaaaa-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', '{A,N,N,A,X,Y,Z}'),
  ('aaaaaaaa-0000-0000-0000-000000000001',
   '22222222-2222-2222-2222-222222222222', '{B,E,R,T,Q,U,I}');

insert into game_secrets (game_id, bag, rng_seed) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '{E,E,E,N,S}', 4711);

insert into moves (game_id, seq, player_id, kind, score) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 0,
   '11111111-1111-1111-1111-111111111111', 'play', 24);

-- Hilfsfunktion: in die Haut eines angemeldeten Nutzers schlüpfen.
create or replace function act_as(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true
  );
end;
$$;

-- ---------------------------------------------------------------
--  Anna: Teilnehmerin
-- ---------------------------------------------------------------

select act_as('11111111-1111-1111-1111-111111111111');

select is(
  (select count(*)::int from games),
  1,
  'Anna sieht ihre eigene Partie'
);

select is(
  (select count(*)::int from game_players),
  2,
  'Anna sieht beide Sitzplätze samt Punkteständen'
);

select is(
  (select score from game_players where seat = 1),
  31,
  'Der Punktestand des Gegners ist sichtbar'
);

select is(
  (select count(*)::int from racks),
  1,
  'Anna sieht genau ein Rack'
);

select is(
  (select tiles from racks),
  '{A,N,N,A,X,Y,Z}'::text[],
  'und zwar ihr eigenes'
);

select is(
  (select count(*)::int from game_secrets),
  0,
  'Der Beutel bleibt auch für Teilnehmer verschlossen'
);

select is(
  (select count(*)::int from moves),
  1,
  'Das Zugprotokoll ist für Teilnehmer lesbar'
);

select is(
  (select count(*)::int from notification_queue),
  0,
  'Die Benachrichtigungs-Warteschlange ist unsichtbar'
);

-- ---------------------------------------------------------------
--  Bert: der Gegner
-- ---------------------------------------------------------------

select act_as('22222222-2222-2222-2222-222222222222');

select is(
  (select tiles from racks),
  '{B,E,R,T,Q,U,I}'::text[],
  'Bert sieht sein eigenes Rack'
);

select is(
  (select count(*)::int from racks
    where player_id = '11111111-1111-1111-1111-111111111111'),
  0,
  'Bert kommt nicht an Annas Steine'
);

-- ---------------------------------------------------------------
--  Clara: unbeteiligt
-- ---------------------------------------------------------------

select act_as('33333333-3333-3333-3333-333333333333');

select is(
  (select count(*)::int from games),
  0,
  'Clara sieht fremde Partien nicht'
);

select is(
  (select count(*)::int from game_players),
  0,
  'Clara sieht die Teilnehmer fremder Partien nicht'
);

select is(
  (select count(*)::int from racks),
  0,
  'Clara sieht keine fremden Racks'
);

select is(
  (select count(*)::int from moves),
  0,
  'Clara sieht fremde Züge nicht'
);

-- ---------------------------------------------------------------
--  Schreibrechte: Clients dürfen den Spielstand nicht anfassen
-- ---------------------------------------------------------------

select act_as('11111111-1111-1111-1111-111111111111');

-- Wichtige Feinheit: fehlt eine UPDATE-Policy, wirft Postgres keinen Fehler.
-- Die Zeilen sind für das Update schlicht nicht sichtbar, die Anweisung trifft
-- null Zeilen und läuft still durch. Deshalb wird hier das Ergebnis geprüft
-- und nicht auf eine Ausnahme gewartet.
update games set current_seat = 1;

select is(
  (select current_seat from games),
  0::smallint,
  'Anna kann den Spielstand nicht selbst weiterdrehen'
);

update racks set tiles = '{Q,Q,Q,Q,Q,Q,Q}';

select is(
  (select tiles from racks),
  '{A,N,N,A,X,Y,Z}'::text[],
  'Anna kann sich keine besseren Steine geben'
);

-- Beim INSERT ist es anders: die WITH-CHECK-Prüfung schlägt fehl, und das
-- gibt einen echten Fehler.
select throws_ok(
  $$ insert into moves (game_id, seq, player_id, kind, score)
     values ('aaaaaaaa-0000-0000-0000-000000000001', 1,
             '11111111-1111-1111-1111-111111111111', 'play', 999) $$,
  '42501',
  null,
  'Anna kann keine Züge frei erfinden'
);

select throws_ok(
  $$ select apply_move('{}'::jsonb) $$,
  '42501',
  null,
  'apply_move ist für Clients gesperrt'
);

select * from finish();

rollback;
