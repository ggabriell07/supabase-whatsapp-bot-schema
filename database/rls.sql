alter table public.profiles enable row level security;
alter table public.conversation_states enable row level security;
alter table public.financial_events enable row level security;
alter table public.decision_events enable row level security;
alter table public.recent_messages enable row level security;
alter table public.behavioral_signals enable row level security;

create policy "profiles_select_own"
  on public.profiles
  for select
  using (auth.uid() = id);

create policy "profiles_update_own"
  on public.profiles
  for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

create policy "conversation_state_own"
  on public.conversation_states
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "financial_events_own"
  on public.financial_events
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "decision_events_own"
  on public.decision_events
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "recent_messages_own"
  on public.recent_messages
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "behavioral_signals_own"
  on public.behavioral_signals
  for select
  using (auth.uid() = user_id);

-- ai_incidents intentionally has no end-user policy.
-- Operational access should be handled by trusted server-side/service-role paths.
