create index if not exists financial_events_user_date_idx
  on public.financial_events (user_id, event_date desc);

create index if not exists financial_events_user_type_date_idx
  on public.financial_events (user_id, event_type, event_date desc);

create index if not exists recent_messages_user_created_idx
  on public.recent_messages (user_id, created_at desc);

create index if not exists decision_events_user_created_idx
  on public.decision_events (user_id, created_at desc);

create index if not exists behavioral_signals_user_key_observed_idx
  on public.behavioral_signals (user_id, signal_key, observed_at desc);

create index if not exists behavioral_signals_value_gin_idx
  on public.behavioral_signals using gin (signal_value);

create unique index if not exists ai_incidents_fingerprint_open_idx
  on public.ai_incidents (fingerprint)
  where status <> 'resolved';
