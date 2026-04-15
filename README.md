# supabase-whatsapp-bot-schema

Schema PostgreSQL para bots de WhatsApp com LLM — desenvolvido e usado em produção no Flecto.

Cobre estrutura de usuários, transações financeiras, estado de conversa multi-step e histórico para contexto de LLM. Inclui RLS policies para isolamento por usuário.

---

## Por que JSONB em vez de colunas fixas

Bots conversacionais têm dados semi-estruturados por natureza. Um usuário menciona "comprei parcelado em 12x no cartão", outro diz "paguei no pix". Forçar colunas fixas para todos os cenários gera tabelas com muitos NULLs ou migrações constantes.

A estratégia usada aqui: **colunas fixas para o que é sempre consultado** (valor, data, categoria), **JSONB para o que é variável** (metadados, estado de fluxo, histórico de conversa).

---

## Schema completo

### Tabela `users`

```sql
CREATE TABLE users (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone           TEXT UNIQUE NOT NULL,       -- número no formato 5548999999999
  name            TEXT,
  monthly_income  NUMERIC(12,2),
  monthly_limit   NUMERIC(12,2),
  savings_goal    TEXT,

  -- Estado de conversa multi-step
  flow_active     TEXT,                       -- nome do fluxo em andamento
  flow_step       INTEGER DEFAULT 1,
  flow_data       JSONB DEFAULT '{}'::jsonb,  -- dados coletados no fluxo

  -- Gamificação
  streak          INTEGER DEFAULT 0,
  last_entry_date DATE,

  -- Perfil comportamental gerado por LLM
  profile_tags    JSONB DEFAULT '[]'::jsonb,
  -- ex: ["gastador_emocional", "impulsivo_noturno", "controlado_alimentacao"]

  -- Histórico de conversa para contexto do LLM
  recent_messages JSONB DEFAULT '[]'::jsonb,
  -- estrutura: [{"role": "user", "content": "..."}, {"role": "assistant", "content": "..."}]

  -- Onboarding
  onboarding_done BOOLEAN DEFAULT FALSE,
  onboarding_step INTEGER DEFAULT 1,

  -- Assinatura
  status          TEXT DEFAULT 'trial',       -- trial | active | expired
  expires_at      TIMESTAMPTZ,

  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);
```

### Tabela `expenses`

```sql
CREATE TABLE expenses (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID REFERENCES users(id) ON DELETE CASCADE,

  amount          NUMERIC(12,2) NOT NULL,
  category        TEXT NOT NULL,
  -- categorias sugeridas: alimentacao, transporte, lazer, saude,
  --   moradia, educacao, vestuario, assinaturas, outros

  description     TEXT,
  expense_date    DATE NOT NULL,              -- data real do gasto (pode ser retroativo)
  created_at      TIMESTAMPTZ DEFAULT NOW(),  -- data do registro no sistema

  -- Contexto comportamental
  emotional_state TEXT,
  -- ex: ansioso, entediado, feliz, neutro, estressado

  was_planned     BOOLEAN DEFAULT FALSE,
  payment_method  TEXT,
  -- ex: credito, debito, pix, dinheiro, boleto

  -- Parcelamento
  is_installment  BOOLEAN DEFAULT FALSE,
  total_installments INTEGER,
  installment_number INTEGER,
  installment_group_id UUID               -- agrupa parcelas da mesma compra
);
```

### Tabela `installments`

```sql
CREATE TABLE installments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
  group_id        UUID NOT NULL,              -- mesmo group_id das expenses

  description     TEXT NOT NULL,
  total_amount    NUMERIC(12,2) NOT NULL,
  installment_value NUMERIC(12,2) NOT NULL,
  total_installments INTEGER NOT NULL,
  paid_installments  INTEGER DEFAULT 0,

  due_day         INTEGER NOT NULL,           -- dia do mês do vencimento (1-31)
  start_month     DATE NOT NULL,
  end_month       DATE NOT NULL,

  is_active       BOOLEAN DEFAULT TRUE,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);
```

### Tabela `incomes`

```sql
CREATE TABLE incomes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID REFERENCES users(id) ON DELETE CASCADE,

  amount          NUMERIC(12,2) NOT NULL,
  category        TEXT NOT NULL,
  -- ex: salario, freelance, aluguel, presente, outros

  description     TEXT,
  income_date     DATE NOT NULL,
  payment_method  TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);
```

---

## Queries de produção

### Saldo do mês atual

```sql
SELECT
  COALESCE(SUM(i.amount), 0) AS total_income,
  COALESCE(SUM(e.amount), 0) AS total_expenses,
  COALESCE(SUM(i.amount), 0) - COALESCE(SUM(e.amount), 0) AS balance
FROM users u
LEFT JOIN incomes  i ON i.user_id = u.id
  AND DATE_TRUNC('month', i.income_date)  = DATE_TRUNC('month', NOW())
LEFT JOIN expenses e ON e.user_id = u.id
  AND DATE_TRUNC('month', e.expense_date) = DATE_TRUNC('month', NOW())
WHERE u.phone = $1;
```

### Gastos por categoria no mês

```sql
SELECT
  category,
  SUM(amount) AS total,
  COUNT(*)    AS count,
  ROUND(SUM(amount) / SUM(SUM(amount)) OVER () * 100, 1) AS pct
FROM expenses
WHERE user_id    = $1
  AND DATE_TRUNC('month', expense_date) = DATE_TRUNC('month', NOW())
GROUP BY category
ORDER BY total DESC;
```

### Score financeiro 0–100

```sql
WITH month_data AS (
  SELECT
    u.monthly_limit,
    COALESCE(SUM(e.amount), 0) AS total_spent,
    COALESCE(SUM(CASE WHEN e.was_planned THEN e.amount ELSE 0 END), 0) AS planned_spent,
    COUNT(DISTINCT e.expense_date) AS active_days
  FROM users u
  LEFT JOIN expenses e ON e.user_id = u.id
    AND DATE_TRUNC('month', e.expense_date) = DATE_TRUNC('month', NOW())
  WHERE u.id = $1
  GROUP BY u.monthly_limit
)
SELECT
  ROUND(
    -- 40% peso: proporção de gastos planejados
    (CASE WHEN total_spent > 0
      THEN (planned_spent / total_spent) ELSE 1 END * 40)
    -- 40% peso: uso do limite (penaliza estouro)
    + (CASE WHEN monthly_limit > 0
      THEN GREATEST(0, 1 - total_spent / monthly_limit) ELSE 0.5 END * 40)
    -- 20% peso: consistência de registro (dias ativos no mês)
    + (LEAST(active_days, 20) / 20.0 * 20)
  ) AS score
FROM month_data;
```

### Previsão de estouro do limite

```sql
WITH pace AS (
  SELECT
    u.monthly_limit,
    COALESCE(SUM(e.amount), 0) AS spent_so_far,
    EXTRACT(DAY FROM NOW())    AS days_elapsed
  FROM users u
  LEFT JOIN expenses e ON e.user_id = u.id
    AND DATE_TRUNC('month', e.expense_date) = DATE_TRUNC('month', NOW())
  WHERE u.id = $1
  GROUP BY u.monthly_limit
)
SELECT
  monthly_limit,
  spent_so_far,
  ROUND(spent_so_far / NULLIF(days_elapsed, 0), 2) AS daily_rate,
  ROUND(
    (monthly_limit - spent_so_far)
    / NULLIF(spent_so_far / NULLIF(days_elapsed, 0), 0)
  ) AS days_until_limit
FROM pace;
```

### Atualizar histórico de conversa (mantém só as últimas 20 mensagens)

```sql
UPDATE users
SET recent_messages = (
  SELECT jsonb_agg(msg)
  FROM (
    SELECT msg
    FROM jsonb_array_elements(
      recent_messages || $2::jsonb  -- $2 = novo array de mensagens a adicionar
    ) AS msg
    ORDER BY ordinality DESC
    LIMIT 20
  ) sub
),
updated_at = NOW()
WHERE id = $1;
```

---

## RLS Policies (Row Level Security)

```sql
-- Habilitar RLS nas tabelas
ALTER TABLE users     ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenses  ENABLE ROW LEVEL SECURITY;
ALTER TABLE incomes   ENABLE ROW LEVEL SECURITY;
ALTER TABLE installments ENABLE ROW LEVEL SECURITY;

-- Policy: usuário só acessa seus próprios dados
CREATE POLICY "users_own_data" ON expenses
  FOR ALL USING (user_id = auth.uid());

CREATE POLICY "users_own_data" ON incomes
  FOR ALL USING (user_id = auth.uid());

CREATE POLICY "users_own_data" ON installments
  FOR ALL USING (user_id = auth.uid());
```

> **Nota:** em bots WhatsApp o acesso ao banco é feito via service role key no backend (n8n), então RLS não aplica para as operações do bot. As policies protegem o acesso eventual via cliente (dashboards, apps mobile). Para o bot, use sempre a service role key em variável de ambiente, nunca no frontend.

---

## Indexes recomendados

```sql
-- Queries de relatório mensal são as mais frequentes
CREATE INDEX idx_expenses_user_date  ON expenses  (user_id, expense_date);
CREATE INDEX idx_incomes_user_date   ON incomes   (user_id, income_date);
CREATE INDEX idx_expenses_category   ON expenses  (user_id, category);
CREATE INDEX idx_installments_active ON installments (user_id, is_active);

-- Lookup de usuário por telefone (toda mensagem do WhatsApp faz essa query)
CREATE INDEX idx_users_phone ON users (phone);
```

---

## Migrations

Estrutura recomendada de pastas para versionar as migrations:

```
/supabase
  /migrations
    001_create_users.sql
    002_create_expenses.sql
    003_create_incomes.sql
    004_create_installments.sql
    005_add_profile_tags.sql
    006_add_recent_messages.sql
    007_add_indexes.sql
```

Use o CLI do Supabase para aplicar:
```bash
supabase db push
```

---

## Referências

- [Supabase Docs — Row Level Security](https://supabase.com/docs/guides/auth/row-level-security)
- [PostgreSQL JSONB](https://www.postgresql.org/docs/current/datatype-json.html)
- [Supabase CLI](https://supabase.com/docs/reference/cli)
