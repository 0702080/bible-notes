-- ─────────────────────────────────────────────────────────────
-- 성경 통독표 전용 수파베이스 준비 SQL
--
-- 쓰는 곳: 수파베이스 대시보드 → '통독표' 프로젝트 → 왼쪽 SQL Editor
--          아래를 통째로 복사해 붙여넣고 [Run] 한 번만 누르면 됩니다.
--          여러 번 눌러도 망가지지 않습니다.
-- ─────────────────────────────────────────────────────────────

-- 1) 사람 ─ 이름과 친구 코드
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text,
  friend_code text unique,
  created_at  timestamptz default now()
);

-- 2) 진도 ─ 통독표는 id='s:tongdok' 한 줄만 씁니다
create table if not exists public.notes (
  user_id    uuid not null references auth.users(id) on delete cascade,
  id         text not null,
  data       jsonb,
  updated_at bigint default 0,
  deleted    boolean default false,
  visibility text default 'private',
  primary key (user_id, id)
);

-- 3) 친구 관계
create table if not exists public.friendships (
  requester uuid not null references auth.users(id) on delete cascade,
  addressee uuid not null references auth.users(id) on delete cascade,
  status    text not null default 'pending',
  created_at timestamptz default now(),
  primary key (requester, addressee)
);
create index if not exists friendships_addressee_idx on public.friendships(addressee);

-- ── 새로 가입하면 친구 코드를 저절로 만들어 준다 ──────────────
create or replace function public.new_user_profile()
returns trigger language plpgsql security definer set search_path = public as $$
declare c text;
begin
  loop
    -- 헷갈리는 글자(0,O,1,I)는 빼고 6자리
    c := (select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
                                   (floor(random()*32)+1)::int, 1), '')
          from generate_series(1,6));
    exit when not exists (select 1 from public.profiles where friend_code = c);
  end loop;
  insert into public.profiles(id, friend_code) values (new.id, c)
    on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.new_user_profile();

-- 이미 가입한 사람에게도 코드를 만들어 준다 (처음 한 번)
insert into public.profiles(id, friend_code)
select u.id,
       (select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
                                 (floor(random()*32)+1)::int, 1), '')
        from generate_series(1,6))
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id)
on conflict (id) do nothing;

-- ── 나와 이어진 사람인지 확인하는 도우미 ────────────────────
create or replace function public.is_linked(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.friendships f
    where (f.requester = auth.uid() and f.addressee = other)
       or (f.addressee = auth.uid() and f.requester = other)
  );
$$;

create or replace function public.is_friend(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester = auth.uid() and f.addressee = other)
        or (f.addressee = auth.uid() and f.requester = other))
  );
$$;

-- ── 보안 규칙 (내 것과 친구 것만 보이게) ─────────────────────
alter table public.profiles    enable row level security;
alter table public.notes       enable row level security;
alter table public.friendships enable row level security;

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_linked(id));

drop policy if exists profiles_write on public.profiles;
create policy profiles_write on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists notes_read on public.notes;
create policy notes_read on public.notes for select to authenticated
  using (user_id = auth.uid()
         or (visibility = 'friends' and deleted is not true and public.is_friend(user_id)));

drop policy if exists notes_insert on public.notes;
create policy notes_insert on public.notes for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists notes_update on public.notes;
create policy notes_update on public.notes for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists notes_delete on public.notes;
create policy notes_delete on public.notes for delete to authenticated
  using (user_id = auth.uid());

drop policy if exists friendships_read on public.friendships;
create policy friendships_read on public.friendships for select to authenticated
  using (requester = auth.uid() or addressee = auth.uid());

-- 수락: 신청받은 사람만 'accepted' 로 바꿀 수 있다
drop policy if exists friendships_accept on public.friendships;
create policy friendships_accept on public.friendships for update to authenticated
  using (addressee = auth.uid()) with check (addressee = auth.uid());

drop policy if exists friendships_cancel on public.friendships;
create policy friendships_cancel on public.friendships for delete to authenticated
  using (requester = auth.uid() or addressee = auth.uid());

-- ── 친구 코드로 신청하기 (앱의 '친구 신청' 단추가 부르는 것) ──
create or replace function public.request_friend(code text)
returns text language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); other uuid; st text;
begin
  if me is null then return 'login'; end if;
  select id into other from public.profiles
   where upper(friend_code) = upper(btrim(code));
  if other is null then return 'notfound'; end if;
  if other = me   then return 'self';     end if;

  select status into st from public.friendships
   where (requester = me and addressee = other)
      or (requester = other and addressee = me);

  if st = 'accepted' then return 'already'; end if;

  -- 상대가 먼저 신청해 둔 상태면 바로 친구가 된다
  if exists (select 1 from public.friendships
              where requester = other and addressee = me and status = 'pending') then
    update public.friendships set status = 'accepted'
     where requester = other and addressee = me;
    return 'accepted';
  end if;

  if st = 'pending' then return 'already'; end if;

  insert into public.friendships(requester, addressee, status)
  values (me, other, 'pending')
  on conflict (requester, addressee) do nothing;
  return 'requested';
end $$;

revoke all on function public.request_friend(text) from public;
grant execute on function public.request_friend(text) to authenticated;
