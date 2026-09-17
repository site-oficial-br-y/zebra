-- ZEBRA · cadastro, partidas e ranking
-- Rodar inteiro no SQL Editor do Supabase. Pode rodar de novo sem quebrar nada.

-- ---------------------------------------------------------------- perfis
create table if not exists zebra_perfis (
  id          uuid primary key references auth.users(id) on delete cascade,
  apelido     text not null check (char_length(apelido) between 2 and 18),
  criado_em   timestamptz not null default now()
);

-- apelido único, sem diferenciar maiúscula de minúscula
create unique index if not exists zebra_perfis_apelido_unico
  on zebra_perfis (lower(apelido));

-- ---------------------------------------------------------------- partidas
create table if not exists zebra_partidas (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  overall       smallint not null check (overall between 0 and 99),
  formacao      text not null,
  estilo        text not null,
  campeao       boolean not null default false,
  eliminado_em  text,                 -- 'grupos', 'Oitavas', 'Final'...
  gols_pro      smallint not null default 0,
  gols_contra   smallint not null default 0,
  maior_goleada smallint not null default 0,
  escalacao     jsonb,                -- os onze, para poder remontar o time
  criado_em     timestamptz not null default now()
);
create index if not exists zebra_partidas_user on zebra_partidas (user_id);
create index if not exists zebra_partidas_campeao on zebra_partidas (campeao) where campeao;

-- ---------------------------------------------------------------- RLS
alter table zebra_perfis   enable row level security;
alter table zebra_partidas enable row level security;

drop policy if exists "perfil: qualquer um lê"        on zebra_perfis;
drop policy if exists "perfil: dono cria"             on zebra_perfis;
drop policy if exists "perfil: dono edita"            on zebra_perfis;
drop policy if exists "perfil: dono apaga"            on zebra_perfis;
-- leitura pública: o ranking precisa mostrar o apelido de todo mundo
create policy "perfil: qualquer um lê" on zebra_perfis for select using (true);
create policy "perfil: dono cria"      on zebra_perfis for insert with check (auth.uid() = id);
create policy "perfil: dono edita"     on zebra_perfis for update using (auth.uid() = id);
create policy "perfil: dono apaga"     on zebra_perfis for delete using (auth.uid() = id);

drop policy if exists "partida: qualquer um lê" on zebra_partidas;
drop policy if exists "partida: dono cria"      on zebra_partidas;
drop policy if exists "partida: dono apaga"     on zebra_partidas;
create policy "partida: qualquer um lê" on zebra_partidas for select using (true);
create policy "partida: dono cria"      on zebra_partidas for insert with check (auth.uid() = user_id);
create policy "partida: dono apaga"     on zebra_partidas for delete using (auth.uid() = user_id);
-- de propósito NÃO existe policy de update em partidas:
-- resultado publicado não se edita, senão o ranking vira ficção

-- ---------------------------------------------------------------- ranking
-- Uma view faz a conta no banco, então o navegador não baixa todas as partidas.
create or replace view zebra_ranking as
select
  p.id                                             as user_id,
  p.apelido,
  count(j.id)                                      as partidas,
  count(*) filter (where j.campeao)                as titulos,
  coalesce(max(j.overall), 0)                      as melhor_overall,
  coalesce(sum(j.gols_pro) - sum(j.gols_contra), 0) as saldo,
  coalesce(max(j.maior_goleada), 0)                as maior_goleada
from zebra_perfis p
left join zebra_partidas j on j.user_id = p.id
group by p.id, p.apelido;

grant select on zebra_ranking to anon, authenticated;

-- ---------------------------------------------------------------- excluir conta
-- Apagar de auth.users exige privilégio que o navegador não tem.
-- Esta função roda com o dono da função (security definer) mas só apaga
-- quem está chamando, nunca outra pessoa.
create or replace function zebra_excluir_minha_conta()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  eu uuid := auth.uid();
begin
  if eu is null then
    raise exception 'precisa estar logado';
  end if;
  delete from zebra_partidas where user_id = eu;
  delete from zebra_perfis   where id = eu;
  delete from auth.users     where id = eu;   -- encerra a conta de vez
end;
$$;

revoke all on function zebra_excluir_minha_conta() from public, anon;
grant execute on function zebra_excluir_minha_conta() to authenticated;

-- ---------------------------------------------------------------- perfil junto com a conta
-- Antes o navegador criava a conta e só depois inseria o perfil, em duas
-- viagens. Se a segunda falhasse (queda, apelido tomado na corrida), sobrava
-- login sem apelido: a pessoa entrava e não existia no ranking.
-- Agora o perfil nasce dentro da mesma transação do cadastro. Se o apelido
-- estiver em uso, o índice único derruba o insert e a conta inteira não é
-- criada — nunca sobra metade.
create or replace function zebra_perfil_da_conta_nova()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ap text := nullif(trim(new.raw_user_meta_data ->> 'apelido'), '');
begin
  -- Sem apelido informado (ou fora do tamanho), gera um para nunca ficar órfão.
  if ap is null or char_length(ap) < 2 or char_length(ap) > 18 then
    ap := 'zebra' || lpad((floor(random() * 100000))::int::text, 5, '0');
  end if;
  insert into zebra_perfis (id, apelido) values (new.id, ap);
  return new;
end;
$$;

drop trigger if exists zebra_ao_criar_usuario on auth.users;
create trigger zebra_ao_criar_usuario
  after insert on auth.users
  for each row execute function zebra_perfil_da_conta_nova();
