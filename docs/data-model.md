# Data Model

This repository demonstrates a PostgreSQL/Supabase data model for stateful conversational AI systems.

## Core entities

### profiles

Application-level user data linked to `auth.users`.

### conversation_states

Stores explicit flow state so a multi-step interaction does not depend on model memory.

Representative fields:

```text
current_flow
flow_step
flow_data
```

### financial_events

Stores normalized financial facts independently from the original natural-language message.

### decision_events

Stores purchase-decision outcomes and structured context.

### recent_messages

Stores a bounded conversational history that can be used to reconstruct context for downstream AI calls.

### behavioral_signals

Stores distilled signals separately from raw events. This avoids repeatedly recomputing every behavioral feature from the full event history.

### ai_incidents

Demonstrates an operational incident model with severity, fingerprints and recurrence counts.

## Design principles

- conversational state is explicit
- raw events and derived signals are separated
- JSONB is used where flexible structured context is useful
- high-frequency access patterns receive dedicated indexes
- user-facing data is protected through row-level security
- operational incident data is isolated from end-user policies

This is a sanitized reference schema, not a production database dump.
