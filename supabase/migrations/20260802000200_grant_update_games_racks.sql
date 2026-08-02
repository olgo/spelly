-- games und racks haben keine update-Policy - ein UPDATE soll deshalb
-- lautlos null Zeilen treffen, nicht mit "permission denied" scheitern.
-- Dafür wird trotzdem das Basis-Grant gebraucht.

grant update on games to authenticated;
grant update on racks to authenticated;
