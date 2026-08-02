-- watchGame() (game_repository.dart) abonniert Live-Updates auf die
-- games-Zeile per Supabase Realtime, damit ein Zug des Gegners ohne manuelles
-- Neuladen ankommt. Das braucht eine explizite Freischaltung pro Tabelle -
-- fehlte bisher komplett, die Subscription scheiterte mit "channelError".

alter publication supabase_realtime add table games;
