-- respond_invitation() warf beim Annehmen SQLSTATE 42804
-- (datatype_mismatch): der CASE-Ausdruck ("invite_accepted"/"your_turn")
-- verliert im Gegensatz zu einem nackten String-Literal seinen impliziten
-- "unknown"-Typ und lässt sich nicht mehr automatisch auf notification_kind
-- casten. Alle anderen Stellen im Projekt schreiben den Wert direkt hin
-- (kein CASE) und sind deshalb nicht betroffen - hier fehlt der explizite
-- Cast.

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
           (case when gp.seat = 0 then 'invite_accepted' else 'your_turn' end)
             ::notification_kind
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
