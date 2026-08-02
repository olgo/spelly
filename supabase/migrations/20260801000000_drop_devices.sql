-- Push lief bis vor Kurzem über selbst verwaltete FCM-Tokens in dieser
-- Tabelle. Seit der Umstellung auf OneSignal (Zustellung per external_id)
-- wird sie von keinem Client und keiner Edge Function mehr angefasst.

drop table if exists devices;
