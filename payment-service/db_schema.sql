-- Payment Service schema
-- Swap the in-memory map in main.bal for ballerinax/postgresql against this table.

CREATE TABLE IF NOT EXISTS payments (
    payment_id  UUID PRIMARY KEY,
    order_id    UUID NOT NULL,
    customer_id UUID NOT NULL,
    amount      NUMERIC(10, 2) NOT NULL CHECK (amount > 0),
    status      VARCHAR(10) NOT NULL CHECK (status IN ('PENDING', 'SUCCESS', 'FAILED')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payments_order_id ON payments(order_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(status);
