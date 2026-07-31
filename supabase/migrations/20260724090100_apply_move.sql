-- Schreibt einen bereits validierten Zug atomar weg.
-- Die gesamte Regelprüfung passiert vorher in der Edge Function; hier geht es
-- nur noch um Konsistenz: entweder alle sechs Schreibvorgänge oder keiner.

create or replace function apply_move(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_game        games%rowtype;
  v_game_id     uuid := (p->>'game_id')::uuid;
  v_player_id   uuid := (p->>'player_id')::uuid;
  v_adjustment  jsonb;
begin
  -- Zeilensperre: parallele Züge derselben Partie serialisieren sich hier.
  select * into v_game from games where id = v_game_id for update;
  if not found then
    raise exception 'game_not_found';
  end if;

  -- Optimistische Sperre. Schlägt zu, wenn zwischen Laden und Schreiben in der
  -- Edge Function schon ein anderer Zug durchging (Doppel-Tap, Retry).
  if v_game.turn_number <> (p->>'expected_turn')::int then
    raise exception 'stale_turn';
  end if;

  update games set
    board              = p->'board',
    current_seat       = (p->>'next_seat')::smallint,
    turn_number        = v_game.turn_number + 1,
    consecutive_passes = (p->>'consecutive_passes')::smallint,
    tiles_left         = (p->>'tiles_left')::smallint,
    status             = (p->>'status')::game_status,
    winner_id          = nullif(p->>'winner_id', '')::uuid,
    last_move_at       = now(),
    deadline_at        = case
                           when (p->>'status') = 'active'
                           then now() + interval '7 days'
                           else null
                         end
  where id = v_game_id;

  update game_secrets set
    bag = array(select jsonb_array_elements_text(p->'bag'))
  where game_id = v_game_id;

  update racks set
    tiles = array(select jsonb_array_elements_text(p->'rack'))
  where game_id = v_game_id and player_id = v_player_id;

  update game_players set
    score = score + (p->>'score')::int
  where game_id = v_game_id and player_id = v_player_id;

  -- Schlussabrechnung: Restwerte der Racks verrechnen.
  for v_adjustment in select * from jsonb_array_elements(coalesce(p->'adjustments', '[]'::jsonb))
  loop
    update game_players set
      score = score + (v_adjustment->>'delta')::int
    where game_id = v_game_id
      and player_id = (v_adjustment->>'player_id')::uuid;
  end loop;

  insert into moves (game_id, seq, player_id, kind, placements, words, score)
  values (
    v_game_id,
    (p->>'seq')::int,
    v_player_id,
    (p->>'kind')::move_kind,
    coalesce(p->'placements', '[]'::jsonb),
    coalesce(p->'words', '[]'::jsonb),
    (p->>'score')::int
  );

  -- Gewinner erst nach der Schlussabrechnung bestimmen.
  if (p->>'status') = 'finished' and (p->>'winner_id') is null then
    update games set winner_id = (
      select player_id from game_players
      where game_id = v_game_id
      order by score desc
      limit 1
    )
    where id = v_game_id;
  end if;

  return jsonb_build_object(
    'turn_number', v_game.turn_number + 1,
    'next_seat',   (p->>'next_seat')::smallint,
    'status',      p->>'status'
  );
end;
$$;

-- Nur die Edge Function darf das aufrufen, nie ein Client.
revoke execute on function apply_move(jsonb) from public, anon, authenticated;
grant  execute on function apply_move(jsonb) to service_role;
