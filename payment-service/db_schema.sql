-- Payment Service schema
-- Run automatically by docker-compose (mounted into /docker-entrypoint-initdb.d on first start).

CREATE TABLE IF NOT EXISTS payments (
    payment_id  UUID PRIMARY KEY,
    order_id    UUID NOT NULL,
    customer_id UUID NOT NULL,
    amount      NUMERIC(10, 2) NOT NULL CHECK (amount > 0),
    status      VARCHAR(10) NOT NULL CHECK (status IN ('PENDING', 'SUCCESS', 'FAILED', 'REFUNDED')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One row per attempt: a failed payment can be retried, so an order may have
-- several FAILED rows - but the database itself guarantees at most ONE
-- successful payment per order, even if two attempts race each other.
CREATE UNIQUE INDEX IF NOT EXISTS uniq_payments_one_success_per_order
    ON payments(order_id) WHERE status = 'SUCCESS';

CREATE INDEX IF NOT EXISTS idx_payments_order_id ON payments(order_id, created_at);
CREATE INDEX IF NOT EXISTS idx_payments_customer_id ON payments(customer_id);

-- Orders cancelled anywhere in the platform (from orders.status_updated). An
-- order in here is never charged, even if its orders.created event is
-- processed after the cancellation.
CREATE TABLE IF NOT EXISTS cancelled_orders (
    order_id     UUID PRIMARY KEY,
    cancelled_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
