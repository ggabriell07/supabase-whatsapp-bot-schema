create or replace function public.get_recent_conversation(
  p_user_id uuid,
  p_limit integer default 10
)
returns table (
  role text,
  content text,
  created_at timestamptz
)
language sql
stable
security invoker
as $$
  select m.role, m.content, m.created_at
  from public.recent_messages m
  where m.user_id = p_user_id
  order by m.created_at desc
  limit greatest(1, least(coalesce(p_limit, 10), 50));
$$;

create or replace function public.set_conversation_state(
  p_user_id uuid,
  p_current_flow text,
  p_flow_step integer,
  p_flow_data jsonb default '{}'::jsonb
)
returns public.conversation_states
language plpgsql
security invoker
as $$
declare
  result public.conversation_states;
begin
  insert into public.conversation_states (
    user_id,
    current_flow,
    flow_step,
    flow_data,
    updated_at
  )
  values (
    p_user_id,
    p_current_flow,
    p_flow_step,
    coalesce(p_flow_data, '{}'::jsonb),
    now()
  )
  on conflict (user_id)
  do update set
    current_flow = excluded.current_flow,
    flow_step = excluded.flow_step,
    flow_data = excluded.flow_data,
    updated_at = now()
  returning * into result;

  return result;
end;
$$;

create or replace function public.clear_conversation_state(
  p_user_id uuid
)
returns void
language sql
security invoker
as $$
  update public.conversation_states
  set current_flow = null,
      flow_step = null,
      flow_data = '{}'::jsonb,
      updated_at = now()
  where user_id = p_user_id;
$$;
