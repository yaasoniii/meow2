# Payment Service

Owner: Albert

Simulated payment processing and payment-confirmation events for the food-delivery system.

## Responsibilities
- Consumes `orders.created` and charges the order automatically. The charge is simulated: `successRatePercent` in `Config.toml`, 85% by default, succeed.
- Produces `payments.completed` for every attempt
- REST API to retry a failed payment and to look payments up
- Owns the payment/transaction schema (see `db_schema.sql`)

## Endpoints (port 8084)
| Method | Path | Description |
|---|---|---|
| POST | `/payments/initiate` | `{orderId, customerId, amount}`. Starts a payment, typically to retry a failed one. Returns 409 if the order is already paid, and 400 if the ids aren't UUIDs |
| GET | `/payments/{paymentId}` | A single payment (404 if unknown) |
| GET | `/payments/byOrder/{orderId}` | All payment attempts for an order |
| GET | `/payments/health` | Health check |

## Kafka
- Consumes: `orders.created` (uses `orderId`, `customerId`, `totalAmount`)
- Produces: `payments.completed` `{orderId, paymentId, customerId, amount, status: "SUCCESS" | "FAILED", timestamp}`, keyed by `orderId`

**Idempotent.** An order that already has a `SUCCESS` payment is never charged again, whether a redelivered `orders.created` or a manual retry triggers the attempt.

## Persistence
Postgres, with the schema in `db_schema.sql`. Docker Compose mounts it into the `payment-db` container's init directory, so the table is created on first start. If the volume already existed, run it by hand:
```bash
psql -h localhost -p 5433 -U payment_user -d payments -f db_schema.sql
```

## Run locally
```bash
docker compose up -d --build payment-service   # from the repo root
```

## Tests
Integration tests: they need Kafka and `payment-db` up, and the service running on 8084.
```bash
bal test -Cpayment_service.kafkaBootstrapServers=localhost:29092 -Cpayment_service.dbHost=localhost -Cpayment_service.dbPort=5433
```
