-- =========================================================
--  Benachrichtigungen
--  Ersetzt den provisorischen notify_opponent-Trigger aus schema.sql.
-- =========================================================

create extension if not exists pg_net;
create extension if not exists pg_cron;

drop trigger if exists moves_notify on moves;
drop function if exists notify_opponent();

-- ---------- Outbox ----------
-- Ein Push, der beim Schreiben des Zuges verloren geht, bedeutet: der Gegner
-- erfährt nie, dass er dran ist, und die Partie steht still. Deshalb wird die
-- Absicht zu benachrichtigen in derselben Transaktion wie der Zug festgehalten
-- und erst danach zugestellt.

create type notification_kind as enum ('your_turn', 'reminder', 'game_over');
create type notification_state as enum ('pending', 'sending', 'sent', 'failed');

create table notification_queue (
  id           bigserial primary key,
  recipient_id uuid not null references profiles(id) on delete cascade,
  game_id      uuid not null references games(id) on delete cascade,
  kind         notification_kind not null,
  payload      jsonb not null default '{}'::jsonb,
  state        notification_state not null default 'pending',
  attempts     smallint not null default 0,
  last_error   text,
  created_at   timestamptz not null default now(),
  sent_at      timestamptz
);

create index on notification_queue (state, created_at) where state in ('pending', 'failed');
create index on notification_queue (game_id, kind, created_at);

alter table notification_queue enable row level security;
-- Keine Policy: nur service_role sieht die Warteschlange.

-- Sprache für die Push-Texte. Der Client setzt sie beim Anmelden.
alter table profiles add column if not exists locale text not null default 'de';

-- Badge-Zähler: in wie vielen aktiven Partien ist jemand am Zug?
-- Als Funktion, weil PostgREST zwei Spalten nicht direkt vergleichen kann.
create or replace function turns_waiting(p_user uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
  from game_players gp
  join games g on g.id = gp.game_id
  where gp.player_id = p_user
    and g.status = 'active'
    and g.current_seat = gp.seat;
$$;

grant execute on function turns_waiting(uuid) to service_role, authenticated;

-- ---------- Einreihen nach jedem Zug ----------

create or replace function enqueue_move_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_game       games%rowtype;
  v_recipient  uuid;
  v_kind       notification_kind;
begin
  select * into v_game from games where id = new.game_id;

  -- Empfänger ist immer der andere Spieler.
  select player_id into v_recipient
  from game_players
  where game_id = new.game_id and player_id <> new.player_id;

  if v_recipient is null then
    return new;
  end if;

  if v_game.status = 'finished' then
    v_kind := 'game_over';
  else
    v_kind := 'your_turn';
  end if;

  insert into notification_queue (recipient_id, game_id, kind, payload)
  values (
    v_recipient,
    new.game_id,
    v_kind,
    jsonb_build_object(
      'move_kind',   new.kind,
      'score',       new.score,
      'words',       new.words,
      'seq',         new.seq,
      'actor_id',    new.player_id
    )
  );

  return new;
end;
$$;

create trigger moves_enqueue_notification
  after insert on moves
  for each row execute function enqueue_move_notification();

-- ---------- Sofort-Anstoss ----------
-- Der Cron-Sweep unten würde auch reichen, aber er läuft nur minütlich.
-- Dieser Aufruf holt die typische Zustellzeit auf ein bis zwei Sekunden.
-- Fire and forget: schlägt er fehl, fängt der Sweep den Eintrag wieder ein.

create or replace function kick_push_dispatcher()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets where name = 'push_function_url'),
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')
    ),
    body    := '{}'::jsonb
  );
  return null;
end;
$$;

-- statement-level: ein Anstoss pro Zug reicht, nicht pro Zeile.
create trigger notification_queue_kick
  after insert on notification_queue
  for each statement execute function kick_push_dispatcher();

-- ---------- Arbeitspakete holen ----------
-- skip locked erlaubt mehrere parallele Dispatcher-Instanzen, ohne dass
-- derselbe Eintrag zweimal verschickt wird.

create or replace function claim_notifications(p_limit int default 50)
returns setof notification_queue
language sql
security definer
set search_path = public
as $$
  update notification_queue q
  set state = 'sending', attempts = attempts + 1
  where q.id in (
    select id from notification_queue
    where state = 'pending'
       or (state = 'failed' and attempts < 5 and created_at > now() - interval '2 days')
    order by created_at
    limit p_limit
    for update skip locked
  )
  returning q.*;
$$;

revoke execute on function claim_notifications(int) from public, anon, authenticated;
grant  execute on function claim_notifications(int) to service_role;

-- ---------- Erinnerung nach 24 Stunden ----------
-- Dedupliziert über den Zeitstempel: eine Erinnerung gilt nur, wenn seit dem
-- letzten Zug noch keine verschickt wurde.

create or replace function enqueue_reminders()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  with due as (
    select g.id as game_id, gp.player_id
    from games g
    join game_players gp
      on gp.game_id = g.id and gp.seat = g.current_seat
    where g.status = 'active'
      and g.last_move_at < now() - interval '24 hours'
      and not exists (
        select 1 from notification_queue n
        where n.game_id = g.id
          and n.kind = 'reminder'
          and n.created_at > g.last_move_at
      )
  )
  insert into notification_queue (recipient_id, game_id, kind)
  select player_id, game_id, 'reminder' from due;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ---------- Auto-Aufgabe bei Fristablauf ----------

create or replace function sweep_expired_games()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  with expired as (
    select g.id,
           (select player_id from game_players
             where game_id = g.id and seat <> g.current_seat) as winner,
           (select player_id from game_players
             where game_id = g.id and seat  = g.current_seat) as loser
    from games g
    where g.status = 'active' and g.deadline_at < now()
  ),
  closed as (
    update games g
    set status = 'finished', winner_id = e.winner, deadline_at = null
    from expired e
    where g.id = e.id
    returning g.id, e.winner, e.loser
  ),
  logged as (
    insert into moves (game_id, seq, player_id, kind, score)
    select c.id,
           (select coalesce(max(seq), -1) + 1 from moves m where m.game_id = c.id),
           c.loser, 'timeout', 0
    from closed c
    returning game_id
  )
  select count(*) into v_count from logged;

  return v_count;
end;
$$;

-- Der moves-Trigger benachrichtigt den Gewinner automatisch mit; der Verlierer
-- bekommt seine Meldung über diesen zusätzlichen Eintrag.
-- (Bei Bedarf hier analog ein insert für c.loser ergänzen.)

-- ---------- Zeitpläne ----------

select cron.schedule(
  'push-sweep',
  '* * * * *',
  $$ select net.http_post(
       url     := (select decrypted_secret from vault.decrypted_secrets where name = 'push_function_url'),
       headers := jsonb_build_object(
         'Content-Type',  'application/json',
         'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')
       ),
       body    := '{}'::jsonb
     ) $$
);

select cron.schedule('reminders',      '17 * * * *', $$ select enqueue_reminders() $$);
select cron.schedule('expire-games',   '37 * * * *', $$ select sweep_expired_games() $$);

-- Aufräumen: zugestellte Einträge nach zwei Wochen entfernen.
select cron.schedule(
  'prune-notifications',
  '0 4 * * *',
  $$ delete from notification_queue
     where state = 'sent' and sent_at < now() - interval '14 days' $$
);

-- ---------- Secrets anlegen ----------
-- select vault.create_secret('https://<ref>.supabase.co/functions/v1/send-push', 'push_function_url');
-- select vault.create_secret('<service-role-key>', 'service_role_key');
