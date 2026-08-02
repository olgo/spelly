-- game_secrets und notification_queue haben RLS ohne jede Policy - das
-- ist Absicht (siehe init_schema.sql / notifications.sql): normale
-- Clients sollen null Zeilen sehen, nicht aber einen Fehler bekommen.
-- Für "RLS ohne Policy liefert leise null Zeilen" braucht es trotzdem
-- das Basis-Grant, sonst meldet Postgres "permission denied for table"
-- statt einfach leer zu antworten.

grant select on game_secrets to authenticated;
grant select on notification_queue to authenticated;
