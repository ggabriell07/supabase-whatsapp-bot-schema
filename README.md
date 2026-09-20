# PostgreSQL / Supabase Schema for Stateful Conversational AI

Sanitized reference data architecture for conversational AI products that need **persistent state, structured events, behavioral signals and row-level security**.

The repository originated from patterns used while building Flectos, but it is intentionally generalized and contains no production user data or private database dump.

## Why this repository exists

LLM applications often begin with a message table and quickly accumulate state inside prompts or workflow variables.

That approach becomes difficult to operate when the product needs:

- multi-step flows
- structured business events
- explicit conversational state
- user isolation
- derived behavioral signals
- incident investigation
- bounded conversation context

This repository separates those concerns into dedicated PostgreSQL entities.

## Structure

```text
database/
  schema.sql
  indexes.sql
  rls.sql
  functions.sql
  seed.example.sql

docs/
  data-model.md
```

## Data model

```text
auth.users
    │
    ↓
profiles
    ├── conversation_states
    ├── financial_events
    ├── decision_events
    ├── recent_messages
    └── behavioral_signals

operational domain
    └── ai_incidents
```

## Key patterns

### Explicit conversation state

`conversation_states` stores:

- current flow
- current step
- structured flow data
- last update time

This allows the application to continue multi-step interactions without depending on LLM memory.

### Structured events

Financial and decision events are stored independently from raw conversational text.

This makes reporting, evaluation and downstream behavioral analysis easier.

### Behavioral signals

Derived signals are separated from raw events.

A signal can include a confidence value and optional expiration time so the product can reason over recent behavioral context without recomputing every historical event for every model call.

### JSONB where flexibility is useful

Flexible context is stored in JSONB, while core searchable fields remain normalized relational columns.

### Row-level security

The example RLS policies demonstrate per-user isolation using Supabase `auth.uid()`.

Operational incident data is intentionally separated from end-user RLS paths and should be accessed only through trusted server-side/service-role flows.

## Apply in a development Supabase project

Run the files in this order:

```text
database/schema.sql
database/indexes.sql
database/rls.sql
database/functions.sql
```

The seed file contains only commented synthetic examples because profile IDs must reference real records from `auth.users`.

## Functions

The repository includes examples for:

- retrieving bounded recent conversation context
- setting/upserting conversation state
- clearing completed flow state

## Security note

This is a **sanitized reference implementation**.

It does not contain:

- production database credentials
- user phone numbers
- production UUIDs
- private operational data
- production schema dumps
- proprietary business logic

## Production context

These patterns are related to the data architecture behind [Flectos](https://github.com/ggabriell07/flectos), a Behavioral Decision Intelligence product.

The objective of this public repository is to demonstrate PostgreSQL/Supabase engineering patterns without exposing the private application database.

## Next steps

- add migration-based versioning
- add pgTAP database tests
- add synthetic performance fixtures
- benchmark conversation-history queries
- document retention strategies for AI context
- add example materialized views for behavioral aggregates
