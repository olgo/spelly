-- Gehostete Supabase-Projekte grantet die Plattform beim Anlegen
-- automatisch Basiszugriff auf public-Tabellen für anon/authenticated/
-- service_role. Eine frische lokale CLI-Instanz (und `supabase test db`
-- darauf) tut das nicht zuverlässig, deshalb schlägt sonst schon der
-- GRANT vor der eigentlichen RLS-Policy fehl ("permission denied for
-- table games"). Die Policies bleiben die eigentliche Grenze: Tabellen
-- ohne Policy liefern trotz Grant weiterhin keine Zeilen.

grant select, update on profiles to authenticated;
grant select on games to authenticated;
grant select on game_players to authenticated;
grant select on racks to authenticated;
grant select on moves to authenticated;
grant insert on word_reports to authenticated;
grant select, insert, update, delete on matchmaking_queue to authenticated;
grant select on app_release to authenticated, anon;
