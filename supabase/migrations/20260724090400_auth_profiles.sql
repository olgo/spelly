-- Registrierung: Supabase legt die Zeile in auth.users an, das Profil muss
-- mitkommen. Ohne Trigger hätte man kurzzeitig angemeldete Nutzer ohne
-- Anzeigenamen – und genau in dem Moment ruft der Client die Spielerliste auf.

-- Anzeigenamen sollen unterscheidbar sein, ohne dass die Registrierung
-- deshalb fehlschlägt: kollidiert ein Name, hängt der Trigger eine Zahl an.
create or replace function unique_display_name(p_wanted text)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  v_base text := nullif(btrim(p_wanted), '');
  v_name text;
  v_n    int := 1;
begin
  v_base := coalesce(v_base, 'Spieler');
  v_name := v_base;

  while exists (select 1 from profiles where lower(display_name) = lower(v_name)) loop
    v_n := v_n + 1;
    v_name := v_base || ' ' || v_n;
  end loop;

  return v_name;
end;
$$;

create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into profiles (id, display_name, locale)
  values (
    new.id,
    unique_display_name(
      coalesce(
        new.raw_user_meta_data->>'display_name',
        split_part(new.email, '@', 1)
      )
    ),
    coalesce(new.raw_user_meta_data->>'locale', 'de')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- Umbenennen erlaubt, aber nicht auf einen belegten Namen.
create unique index profiles_display_name_key
  on profiles (lower(display_name));

-- Die Web-App zählt als eigene Plattform: dort kommen Web-Push-Tokens an,
-- keine nativen.
alter table devices drop constraint if exists devices_platform_check;
alter table devices add constraint devices_platform_check
  check (platform in ('ios', 'android', 'web'));
