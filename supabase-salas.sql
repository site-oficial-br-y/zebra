-- ZEBRA · salas do duelo online
-- Rodar inteiro no SQL Editor do Supabase. Pode rodar de novo sem quebrar nada.
--
-- Uma sala é uma partida entre dois amigos, identificada por um código de
-- cinco caracteres. O estado do duelo (os times montados, a formação e a
-- postura de cada um) mora no jsonb, e o Realtime avisa os dois navegadores
-- a cada mudança. Como o estado é do banco, ninguém precisa estar online ao
-- mesmo tempo: dá para montar hoje e o outro montar amanhã.

create table if not exists zebra_salas (
  codigo     text primary key check (codigo ~ '^[A-Z0-9]{5}$'),
  base       text not null check (base in ('lendas','atuais','misto')),
  j1         uuid not null references auth.users(id) on delete cascade,
  j2         uuid references auth.users(id) on delete cascade,
  -- times/overs/forms/estilos: os dois lados, no mesmo formato do modo local
  estado     jsonb not null default '{"times":[],"overs":[],"forms":[],"estilos":[]}'::jsonb,
  vez        smallint not null default 1 check (vez in (1, 2)),
  fase       text not null default 'esperando'
             check (fase in ('esperando', 'montando', 'pronto', 'fim')),
  resultado  jsonb,
  criada_em  timestamptz not null default now(),
  mexida_em  timestamptz not null default now()
);

-- Quem já foi levado, pelos dois lados juntos. É esta lista que faz o jogador
-- sumir da tela do outro no instante em que alguém clica nele.
alter table zebra_salas add column if not exists levados text[] not null default '{}';

create index if not exists zebra_salas_j1 on zebra_salas (j1);
create index if not exists zebra_salas_j2 on zebra_salas (j2);

-- ---------------------------------------------------------------- RLS
alter table zebra_salas enable row level security;

-- Só os dois da sala enxergam a sala. Quem só tem o código entra pela função
-- entrar_sala() abaixo, que roda como dono e não depende desta política.
drop policy if exists zebra_salas_le on zebra_salas;
create policy zebra_salas_le on zebra_salas for select
  using (auth.uid() = j1 or auth.uid() = j2);

-- Escrever direto na tabela ninguém escreve: tudo passa pelas funções, que
-- conferem de quem é a vez. Sem política de insert/update/delete, o cliente
-- não consegue se dar um time pronto nem jogar fora da vez.

-- ---------------------------------------------------------------- funções
-- Código curto e legível em voz alta: sem O, 0, I e 1, que a pessoa erra ao
-- ditar no WhatsApp.
create or replace function zebra_codigo_novo() returns text
language plpgsql as $$
declare
  alfabeto constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  tentativa text;
  i int;
begin
  for tentativa_n in 1..20 loop
    tentativa := '';
    for i in 1..5 loop
      tentativa := tentativa || substr(alfabeto, 1 + floor(random() * length(alfabeto))::int, 1);
    end loop;
    if not exists (select 1 from zebra_salas where codigo = tentativa) then
      return tentativa;
    end if;
  end loop;
  raise exception 'não consegui um código livre';
end $$;

create or replace function criar_sala(p_base text)
returns zebra_salas
language plpgsql security definer set search_path = public as $$
declare nova zebra_salas;
begin
  if auth.uid() is null then raise exception 'precisa estar logado'; end if;
  insert into zebra_salas (codigo, base, j1)
  values (zebra_codigo_novo(), p_base, auth.uid())
  returning * into nova;
  return nova;
end $$;

create or replace function entrar_sala(p_codigo text)
returns zebra_salas
language plpgsql security definer set search_path = public as $$
declare sala zebra_salas;
begin
  if auth.uid() is null then raise exception 'precisa estar logado'; end if;
  select * into sala from zebra_salas where codigo = upper(p_codigo);
  if not found then raise exception 'sala não encontrada'; end if;
  -- voltar para a própria sala não é entrar de novo
  if sala.j1 = auth.uid() or sala.j2 = auth.uid() then return sala; end if;
  if sala.j2 is not null then raise exception 'essa sala já tem dois jogadores'; end if;
  update zebra_salas
     set j2 = auth.uid(), fase = 'montando', mexida_em = now()
   where codigo = sala.codigo
  returning * into sala;
  return sala;
end $$;

-- Fecha os onze de quem está na vez e passa a bola para o outro. O banco é
-- quem decide de quem é a vez: o navegador só manda o time.
create or replace function salvar_time(
  p_codigo text, p_time jsonb, p_over numeric, p_form jsonb, p_estilo jsonb)
returns zebra_salas
language plpgsql security definer set search_path = public as $$
declare sala zebra_salas; eu int; e jsonb;
begin
  select * into sala from zebra_salas where codigo = upper(p_codigo);
  if not found then raise exception 'sala não encontrada'; end if;
  eu := case when sala.j1 = auth.uid() then 1
             when sala.j2 = auth.uid() then 2 end;
  if eu is null then raise exception 'você não é dessa sala'; end if;
  if sala.fase = 'esperando' then raise exception 'o adversário ainda não entrou'; end if;
  if sala.fase <> 'montando' then raise exception 'esta sala já fechou os times'; end if;
  -- os dois montam ao mesmo tempo: não há vez, só não se fecha duas vezes
  if sala.estado->'times'->(eu - 1) is not null then
    raise exception 'você já fechou os onze';
  end if;

  e := sala.estado;
  e := jsonb_set(e, array['times',   (eu - 1)::text], p_time,   true);
  e := jsonb_set(e, array['overs',   (eu - 1)::text], to_jsonb(p_over),  true);
  e := jsonb_set(e, array['forms',   (eu - 1)::text], p_form,   true);
  e := jsonb_set(e, array['estilos', (eu - 1)::text], p_estilo, true);

  update zebra_salas
     set estado = e,
         fase = case when e->'times'->0 is not null and e->'times'->1 is not null
                     then 'pronto' else 'montando' end,
         mexida_em = now()
   where codigo = sala.codigo
  returning * into sala;
  return sala;
end $$;

-- Primeiro a clicar leva. O update condicional é a trava: se o id já entrou
-- na lista, nenhuma linha é tocada e quem chegou depois recebe o aviso. Dois
-- cliques no mesmo instante não passam os dois, porque o update serializa a
-- linha da sala.
create or replace function pegar_jogador(p_codigo text, p_id text)
returns zebra_salas
language plpgsql security definer set search_path = public as $$
declare sala zebra_salas;
begin
  select * into sala from zebra_salas where codigo = upper(p_codigo);
  if not found then raise exception 'sala não encontrada'; end if;
  if sala.j1 <> auth.uid() and sala.j2 is distinct from auth.uid() then
    raise exception 'você não é dessa sala';
  end if;
  if sala.fase <> 'montando' then raise exception 'a sala não está montando'; end if;

  update zebra_salas
     set levados = levados || p_id, mexida_em = now()
   where codigo = sala.codigo and not (p_id = any(levados))
  returning * into sala;

  if not found then raise exception 'jogador já levado'; end if;
  return sala;
end $$;

-- O resultado é gravado uma vez só, por quem chegar primeiro.
create or replace function fechar_sala(p_codigo text, p_resultado jsonb)
returns zebra_salas
language plpgsql security definer set search_path = public as $$
declare sala zebra_salas;
begin
  select * into sala from zebra_salas where codigo = upper(p_codigo);
  if not found then raise exception 'sala não encontrada'; end if;
  if sala.j1 <> auth.uid() and sala.j2 is distinct from auth.uid() then
    raise exception 'você não é dessa sala';
  end if;
  if sala.fase = 'fim' then return sala; end if;
  update zebra_salas
     set fase = 'fim', resultado = p_resultado, mexida_em = now()
   where codigo = sala.codigo
  returning * into sala;
  return sala;
end $$;

-- ---------------------------------------------------------------- realtime
-- Sem isto os dois navegadores não recebem aviso de mudança.
do $$ begin
  alter publication supabase_realtime add table zebra_salas;
exception when duplicate_object then null; end $$;

-- Sala parada há mais de sete dias não serve para nada. Rodar quando quiser.
-- delete from zebra_salas where mexida_em < now() - interval '7 days';
