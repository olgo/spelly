-- Partie eröffnen. Wie bei apply_move gilt: entweder alles oder nichts.
-- Eine halb angelegte Partie ohne Racks wäre für den Client nicht reparierbar.

create or replace function create_game(p jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_game_id  uuid := gen_random_uuid();
  v_player_a uuid := (p->>'player_a')::uuid;
  v_player_b uuid := (p->>'player_b')::uuid;
  v_board    jsonb;
begin
  if v_player_a = v_player_b then
    raise exception 'same_player';
  end if;

  -- Ein Spieler soll nicht beliebig viele offene Partien gegen denselben
  -- Gegner aufmachen können.
  if exists (
    select 1
    from game_players a
    join game_players b on b.game_id = a.game_id and b.player_id = v_player_b
    join games g        on g.id = a.game_id
    where a.player_id = v_player_a and g.status in ('waiting', 'active')
  ) then
    raise exception 'duplicate_pairing';
  end if;

  -- 225 leere Felder.
  select jsonb_agg(null::jsonb) into v_board from generate_series(1, 225);

  insert into games (id, status, board, current_seat, tiles_left, dict_version, deadline_at)
  values (
    v_game_id,
    'active',
    v_board,
    (p->>'starting_seat')::smallint,
    (p->>'tiles_left')::smallint,
    p->>'dict_version',
    now() + interval '7 days'
  );

  insert into game_secrets (game_id, bag, rng_seed)
  values (
    v_game_id,
    array(select jsonb_array_elements_text(p->'bag')),
    (p->>'rng_seed')::bigint
  );

  insert into game_players (game_id, player_id, seat)
  values (v_game_id, v_player_a, 0), (v_game_id, v_player_b, 1);

  insert into racks (game_id, player_id, tiles)
  values
    (v_game_id, v_player_a, array(select jsonb_array_elements_text(p->'rack_a'))),
    (v_game_id, v_player_b, array(select jsonb_array_elements_text(p->'rack_b')));

  -- Wer anfängt, wird sofort benachrichtigt. Es gibt noch keinen Zug, also
  -- greift der moves-Trigger nicht – der Eintrag muss hier von Hand rein.
  insert into notification_queue (recipient_id, game_id, kind)
  select gp.player_id, v_game_id, 'your_turn'
  from game_players gp
  where gp.game_id = v_game_id and gp.seat = (p->>'starting_seat')::smallint;

  return v_game_id;
end;
$$;

revoke execute on function create_game(jsonb) from public, anon, authenticated;
grant  execute on function create_game(jsonb) to service_role;

-- ---------------------------------------------------------------
-- Gegnersuche: wer wartet gerade auf eine Partie?
-- ---------------------------------------------------------------

create table matchmaking_queue (
  player_id  uuid primary key references profiles(id) on delete cascade,
  joined_at  timestamptz not null default now()
);

alter table matchmaking_queue enable row level security;

create policy matchmaking_own on matchmaking_queue for all
  using (player_id = auth.uid())
  with check (player_id = auth.uid());
