-- 말씀 묵상 노트: 계정, 노트, 친구 (Supabase SQL Editor에 통째로 붙여 넣고 Run)

-- 1) 내 프로필 (이름, 친구 코드)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  friend_code text unique not null,
  created_at timestamptz not null default now()
);

-- 2) 노트 (앱의 노트 한 개 = 한 줄, 내용은 통째로 data에)
create table if not exists public.notes (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  data jsonb not null,
  visibility text not null default 'private' check (visibility in ('private','friends')),
  deleted boolean not null default false,
  updated_at bigint not null default 0,
  primary key (user_id, id)
);
create index if not exists notes_user_updated on public.notes(user_id, updated_at);

-- 3) 친구 (신청한 사람 → 받은 사람, 수락하면 accepted)
create table if not exists public.friendships (
  requester uuid not null references auth.users(id) on delete cascade,
  addressee uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  primary key (requester, addressee),
  check (requester <> addressee)
);

-- 서로 친구인가?
create or replace function public.are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester = a and f.addressee = b) or (f.requester = b and f.addressee = a))
  );
$$;

-- 가입하면 프로필과 친구 코드 자동으로 만들기
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare code text;
begin
  loop
    code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from public.profiles where friend_code = code);
  end loop;
  insert into public.profiles (id, name, friend_code)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', split_part(coalesce(new.email,''), '@', 1), ''),
          code)
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- 친구 코드로 친구 신청 (코드만 알면 신청 가능, 상대가 수락해야 친구)
create or replace function public.request_friend(code text)
returns text language plpgsql security definer set search_path = public as $$
declare other uuid; me uuid := auth.uid();
begin
  if me is null then return 'login'; end if;
  select id into other from public.profiles where friend_code = upper(trim(code));
  if other is null then return 'notfound'; end if;
  if other = me then return 'self'; end if;
  if public.are_friends(me, other) then return 'already'; end if;
  -- 상대가 먼저 신청해 두었으면 바로 친구가 됨
  update public.friendships set status = 'accepted' where requester = other and addressee = me;
  if found then return 'accepted'; end if;
  insert into public.friendships (requester, addressee) values (me, other) on conflict do nothing;
  return 'requested';
end;
$$;

-- 보안: 각 표마다 RLS 켜기
alter table public.profiles enable row level security;
alter table public.notes enable row level security;
alter table public.friendships enable row level security;

-- 프로필: 나, 친구, 친구 신청을 주고받은 사람만 볼 수 있음. 고치는 건 내 것만
drop policy if exists "profiles read" on public.profiles;
create policy "profiles read" on public.profiles for select to authenticated using (
  id = auth.uid()
  or exists (select 1 from public.friendships f
             where (f.requester = auth.uid() and f.addressee = profiles.id)
                or (f.addressee = auth.uid() and f.requester = profiles.id))
);
drop policy if exists "profiles update" on public.profiles;
create policy "profiles update" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- 노트: 내 노트는 다 할 수 있고, 친구 노트는 '친구 공개'인 것만 읽기
drop policy if exists "notes read" on public.notes;
create policy "notes read" on public.notes for select to authenticated using (
  user_id = auth.uid()
  or (visibility = 'friends' and deleted = false and public.are_friends(auth.uid(), user_id))
);
drop policy if exists "notes insert" on public.notes;
create policy "notes insert" on public.notes for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "notes update" on public.notes;
create policy "notes update" on public.notes for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "notes delete" on public.notes;
create policy "notes delete" on public.notes for delete to authenticated using (user_id = auth.uid());

-- 친구: 내가 낀 것만 보기, 받은 신청만 수락, 끊기는 둘 다 가능
drop policy if exists "friends read" on public.friendships;
create policy "friends read" on public.friendships for select to authenticated
  using (requester = auth.uid() or addressee = auth.uid());
drop policy if exists "friends accept" on public.friendships;
create policy "friends accept" on public.friendships for update to authenticated
  using (addressee = auth.uid()) with check (addressee = auth.uid() and status = 'accepted');
drop policy if exists "friends delete" on public.friendships;
create policy "friends delete" on public.friendships for delete to authenticated
  using (requester = auth.uid() or addressee = auth.uid());

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.notes to authenticated;
grant select, update on public.profiles to authenticated;
grant select, update, delete on public.friendships to authenticated;
grant execute on function public.request_friend(text) to authenticated;
grant execute on function public.are_friends(uuid, uuid) to authenticated;
revoke all on public.notes, public.profiles, public.friendships from anon;
