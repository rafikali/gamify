create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  streak_days integer not null default 0,
  total_xp integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.categories (
  id text primary key,
  title text not null,
  description text not null,
  icon_name text not null,
  accent_hex text not null,
  emoji text not null,
  image_url text,
  total_words integer not null default 0,
  mastery_percent numeric not null default 0,
  sort_order integer not null default 0
);

create table if not exists public.words (
  id text primary key,
  category_id text not null references public.categories (id) on delete cascade,
  answer text not null,
  emoji text not null,
  image_url text,
  fun_fact text not null,
  pronunciation_hint text not null
);

create table if not exists public.game_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  category_id text not null references public.categories (id) on delete cascade,
  score integer not null,
  correct_answers integer not null,
  wrong_answers integer not null,
  cleared_all boolean not null default false,
  elapsed_seconds integer not null default 0,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.achievements (
  id text primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  description text not null,
  emoji text not null,
  progress numeric not null default 0,
  unlocked boolean not null default false
);
