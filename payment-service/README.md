# Payment Service

Owner: Albert

Simulated payment processing and payment-confirmation events for the food-delivery system.

## Responsibilities
- REST API to initiate and check the status of a simulated payment
- Consumes `orders.created`, produces `payments.completed` on success/failure
- Owns the payment/transaction schema (see `db_schema.sql`)

## Endpoints
| Method | Path | Description |
|---|---|---|
| POST | `/payments/initiate` | Start a payment for an order. Also used to retry a failed one. |
| GET | `/payments/{paymentId}` | Get a single payment's status |
| GET | `/payments/byOrder/{orderId}` | All payment attempts for an order |
| GET | `/payments/health` | Health check |

## Kafka
- Consumes: `orders.created`
- Produces: `payments.completed` — `{orderId, paymentId, status, timestamp}`

## Persistence
Postgres, schema in `db_schema.sql`. Run it against your `payment-db` container before first use:
```bash
psql -h localhost -p 5433 -U payment_user -d payments -f db_schema.sql
```

## Run locally
```bash
bal run
```
Reads Kafka/DB connection settings from `Config.toml` (defaults match the docker-compose services below).

## Tests
```bash
bal test
```

## Docker
```bash
docker build -t payment-service .
docker run -p 8083:8083 -e KAFKA_BOOTSTRAP=kafka:9092 payment-service
```