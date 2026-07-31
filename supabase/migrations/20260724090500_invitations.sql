-- Herausforderungen laufen als Einladung: die Partie entsteht im Status
-- 'waiting' und wird erst durch Annahme aktiv. Ablehnen ist ausdrücklich
-- vorgesehen – sonst häufen sich bei jemandem, der gerade keine Lust hat,
-- stillschweigend Partien an.

alter type notification_kind add value if not exists 'invite';
alter type notification_kind add value if not exists 'invite_accepted';
alter type notification_kind add value if not exists 'invite_declined';

-- Mehrere gleichzeitige Partien gegen dieselbe Person sind jetzt erlaubt.
-- Nur offene Einladungen werden begrenzt, damit niemand zugespammt wird.
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
  v_status   game_status := coalesce((p->>'status')::game_status, 'waiting');
  v_board    jsonb;
begin
  if v_player_a = v_player_b then
    raise exception 'same_player';
  end if;

  if exists (
    select 1
    from game_players a
    join game_players b on b.game_id = a.game_id and b.player_id = v_player_b
    join games g        on g.id = a.game_id
    where a.player_id = v_player_a and g.status = 'waiting'
  ) then
    raise exception 'invite_pending';
  end if;

  select jsonb_agg(null::jsonb) into v_board from generate_series(1, 225);

  insert into games (id, status, board, current_seat, tiles_left, dict_version, deadline_at)
  values (
    v_game_id, v_status, v_board,
    (p->>'starting_seat')::smallint,
    (p->>'tiles_left')::smallint,
    p->>'dict_version',
    -- Die Zugfrist läuft erst ab Annahme.
    case when v_status = 'active' then now() + interval '7 days' end
  );

  insert into game_secrets (game_id, bag, rng_seed)
  values (
    v_game_id,
    array(select jsonb_array_elements_text(p->'bag')),
    (p->>'rng_seed')::bigint
  );

  -- Sitz 0 gehört immer der einladenden Person.
  insert into game_players (game_id, player_id, seat)
  values (v_game_id, v_player_a, 0), (v_game_id, v_player_b, 1);

  insert into racks (game_id, player_id, tiles)
  values
    (v_game_id, v_player_a, array(select jsonb_array_elements_text(p->'rack_a'))),
    (v_game_id, v_player_b, array(select jsonb_array_elements_text(p->'rack_b')));

  if v_status = 'waiting' then
    insert into notification_queue (recipient_id, game_id, kind)
    values (v_player_b, v_game_id, 'invite');
  else
    insert into notification_queue (recipient_id, game_id, kind)
    select gp.player_id, v_game_id, 'your_turn'
    from game_players gp
    where gp.game_id = v_game_id
      and gp.seat = (p->>'starting_seat')::smallint;
  end if;

  return v_game_id;
end;
$$;

revoke execute on function create_game(jsonb) from public, anon, authenticated;
grant  execute on function create_game(jsonb) to service_role;

-- ---------------------------------------------------------------
--  Annehmen und ablehnen
-- ---------------------------------------------------------------
-- Anders als apply_move darf der Client das direkt aufrufen: hier sind keine
-- verdeckten Informationen im Spiel, die Funktion prüft selbst, dass nur die
-- eingeladene Person antworten kann.

create or replace function respond_invitation(p_game_id uuid, p_accept boolean)
returns game_status
language plpgsql
security definer
set search_path = public
as $$
declare
  v_game    games%rowtype;
  v_seat    smallint;
  v_inviter uuid;
begin
  select * into v_game from games where id = p_game_id for update;
  if not found then
    raise exception 'game_not_found';
  end if;
  if v_game.status <> 'waiting' then
    raise exception 'not_pending';
  end if;

  select seat into v_seat
  from game_players
  where game_id = p_game_id and player_id = auth.uid();

  -- Sitz 1 ist die eingeladene Person. Die einladende kann nicht für sie
  -- annehmen.
  if v_seat is distinct from 1 then
    raise exception 'not_invited';
  end if;

  select player_id into v_inviter
  from game_players where game_id = p_game_id and seat = 0;

  if p_accept then
    update games set
      status       = 'active',
      last_move_at = now(),
      deadline_at  = now() + interval '7 days'
    where id = p_game_id;

    -- Wer anfängt, erfährt es sofort.
    insert into notification_queue (recipient_id, game_id, kind)
    select gp.player_id, p_game_id,
           case when gp.seat = 0 then 'invite_accepted' else 'your_turn' end
    from game_players gp
    where gp.game_id = p_game_id
      and (gp.seat = 0 or gp.seat = v_game.current_seat);

    return 'active'::game_status;
  end if;

  update games set status = 'abandoned', deadline_at = null
  where id = p_game_id;

  insert into notification_queue (recipient_id, game_id, kind)
  values (v_inviter, p_game_id, 'invite_declined');

  return 'abandoned'::game_status;
end;
$$;

grant execute on function respond_invitation(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------
--  Spielerliste
-- ---------------------------------------------------------------
-- Eine Funktion statt einer offenen Abfrage, damit der Client nicht selbst
-- über drei Tabellen joinen muss und nichts sieht, was ihn nichts angeht.

create or replace function list_players()
returns table (
  id             uuid,
  display_name   text,
  open_games     int,
  my_turn_games  int,
  pending_invite uuid,
  invite_from_me boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.display_name,
    coalesce(o.open_games, 0)::int,
    coalesce(o.my_turn_games, 0)::int,
    w.game_id,
    w.from_me
  from profiles p
  left join lateral (
    select
      count(*) filter (where g.status = 'active') as open_games,
      count(*) filter (
        where g.status = 'active' and g.current_seat = mine.seat
      ) as my_turn_games
    from games g
    join game_players mine  on mine.game_id = g.id and mine.player_id = auth.uid()
    join game_players other on other.game_id = g.id and other.player_id = p.id
  ) o on true
  left join lateral (
    select g.id as game_id, mine.seat = 0 as from_me
    from games g
    join game_players mine  on mine.game_id = g.id and mine.player_id = auth.uid()
    join game_players other on other.game_id = g.id and other.player_id = p.id
    where g.status = 'waiting'
    limit 1
  ) w on true
  where p.id <> auth.uid()
  order by coalesce(o.open_games, 0) desc, lower(p.display_name);
$$;

grant execute on function list_players() to authenticated;

-- ---------------------------------------------------------------
--  Versionshinweis
-- ---------------------------------------------------------------
-- Ohne Store gibt es keine automatischen Updates. Der Client vergleicht beim
-- Start seine Version mit dieser Tabelle und weist auf einen neuen Stand hin.

create table app_release (
  platform     text primary key check (platform in ('android', 'web')),
  version      text not null,
  download_url text,
  mandatory    boolean not null default false,
  notes        text,
  updated_at   timestamptz not null default now()
);

alter table app_release enable row level security;

create policy app_release_read on app_release for select
  to authenticated, anon using (true);
