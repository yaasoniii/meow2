# Order Service — DSA612S Assignment 2

Owner: Jason. Central state machine for the Distributed Food Delivery Platform.

## Lifecycle

```
CREATED -> CONFIRMED -> PREPARING -> READY -> OUT_FOR_DELIVERY -> DELIVERED
   \-> CANCELLED (from CREATED, CONFIRMED, or PREPARING)
```

`PREPARING` is also reached automatically when a `payments.completed` event
confirms payment for an order that's currently `CONFIRMED` (see below) — a
client can still drive the same transition manually via the status endpoint.

## Layout

Ballerina only compiles a module's `.bal` files when they sit directly in
that module's own directory (the default module's root, or a `modules/<name>/`
folder) — arbitrary subfolders are silently ignored. So "folders" here means
real Ballerina submodules, each with a distinct responsibility:

```
service.bal                 Default module: the REST API only (HTTP resources, no business
                             logic - it just calls into lifecycle/store/messaging below).

modules/lifecycle/          Pure domain model: Order/OrderStatus/isValidTransition/
                             computeOrderTotal. No Kafka/Mongo/HTTP imports, so it can be
                             unit tested with zero infrastructure running.
  types.bal
  tests/lifecycle_test.bal  All 49 isValidTransition from/to combinations + computeOrderTotal.

modules/store/               MongoDB persistence.
  store.bal                  Client/database/collection setup + CRUD, keyed on lifecycle:Order.

modules/messaging/          Everything Kafka.
  types.bal                  Event payload shapes (orders.created, orders.status_updated,
                              payments.completed).
  producer.bal                Publishes orders.created / orders.status_updated.
  consumer.bal                Consumes payments.completed -> auto CONFIRMED -> PREPARING.

tests/                        Integration tests: exercise the real running HTTP service
                               against real Mongo/Kafka (see Testing below).
```

Dependency direction: `service.bal` (default module) depends on `lifecycle`,
`store`, and `messaging`; `messaging` depends on `store` (to look up/update an
order when a payment confirmation arrives) and `lifecycle`; `store` depends
only on `lifecycle`; `lifecycle` depends on nothing in this project.

## REST API

| Method | Path                     | Description                          |
|--------|--------------------------|---------------------------------------|
| POST   | /orders                  | Create an order (status = CREATED)   |
| GET    | /orders                  | List all orders                       |
| GET    | /orders/{orderId}        | Fetch one order                       |
| PUT    | /orders/{orderId}/status | Advance the order's status            |

## Persistence: MongoDB

Database `order_service`, single collection `orders`. Each order is stored as
one document with its items embedded (no join needed to read an order):

```json
{
  "_id": "ObjectId(...)",            // Mongo-generated, not used by the app
  "orderId": "uuid-string",          // unique index - the key every other service uses
  "customerId": "string",
  "restaurantId": "string",
  "items": [{"itemId": "string", "name": "string", "quantity": 0, "unitPrice": 0.0}],
  "totalAmount": 0.0,
  "status": "CREATED|CONFIRMED|PREPARING|READY|OUT_FOR_DELIVERY|DELIVERED|CANCELLED",
  "createdAt": "ISO-8601 string",
  "updatedAt": "ISO-8601 string"
}
```

A unique index on `orderId` is created at startup (`modules/store/store.bal`'s `init()`).
Status updates are applied with the previous status included in the update
filter (`{orderId, status: previousStatus}`), so two concurrent transition
requests can't silently clobber each other — the loser gets a 409.

## Kafka contract (shared with the whole group)

### Topic: `orders.created`
Produced when an order is first created.
```json
{
  "orderId": "string",
  "customerId": "string",
  "restaurantId": "string",
  "items": [{"itemId": "string", "name": "string", "quantity": 0, "unitPrice": 0.0}],
  "totalAmount": 0.0,
  "timestamp": "ISO-8601 string"
}
```
Consumers: Customer Service, Restaurant Service, Payment Service, Notification Service, Admin Service.

### Topic: `orders.status_updated`
Produced on every valid status transition (manual or auto-advanced).
```json
{
  "orderId": "string",
  "previousStatus": "CREATED|CONFIRMED|PREPARING|READY|OUT_FOR_DELIVERY|DELIVERED|CANCELLED",
  "newStatus": "same enum",
  "timestamp": "ISO-8601 string"
}
```
Consumers: Customer Service, Notification Service, Admin Service.

**Partition key:** `orderId` for both topics, so all events for one order stay ordered on the same partition.

### Topic consumed: `payments.completed`
Owned by the Payment Service, not us. `modules/messaging/consumer.bal` currently assumes:
```json
{"orderId": "string", "status": "COMPLETED", "amount": 0.0, "currency": "string", "timestamp": "ISO-8601 string"}
```
**This is a guess** — confirm the real field names (`status` vs `paymentStatus`,
`"COMPLETED"` vs `"SUCCESS"`, etc.) with whoever owns the Payment Service and
update `PaymentCompletedEvent` in `modules/messaging/types.bal` and the check
in `consumer.bal` accordingly. Only `orderId` and a completed/failed status
are required for the auto-transition to work.

When a `payments.completed` event with status `COMPLETED` arrives for an
order that is currently `CONFIRMED`, the order is atomically moved to
`PREPARING` and `orders.status_updated` is published. Events for orders in
any other state, or for unknown order IDs, are logged and skipped (this
makes the handler idempotent against redelivery and out-of-order events).

## Running locally

```
# from the repo root
docker compose up -d --build
```

This starts Zookeeper, Kafka, MongoDB, and the order service (port 8081).
`order-service` waits for Kafka and MongoDB's healthchecks before starting.

## Testing

Two tiers, because the `store` and `messaging` modules connect to real
infrastructure the moment they initialize — there's no way to "run
everything" without Kafka and MongoDB up. The pure state-machine logic lives
in `modules/lifecycle` specifically so it doesn't have that problem:

Run these from inside `order-service/` (the Ballerina package root):

```
cd order-service

# Pure unit tests: isValidTransition (all 49 from/to combinations) and
# computeOrderTotal. No Docker, no network calls, runs in well under a second.
bal test --tests "order_service.lifecycle:*"

# Everything, including the HTTP API integration tests in tests/ (needs
# Kafka + MongoDB reachable - defaults assume the Compose service names,
# which don't resolve outside the Compose network). Configurables that live
# in a submodule need the fully-qualified -C key: <package>.<module>.<name>.
docker compose -f ../docker-compose.yml up -d zookeeper kafka mongo
bal test -Corder_service.messaging.kafkaBootstrapServers=localhost:29092 \
         -Corder_service.store.mongoHost=localhost
```

The integration tests hit the live HTTP API end-to-end (create, fetch, list,
valid/invalid transitions, 404s) against real Mongo/Kafka. They're tagged
`groups: ["integration"]` in case you want `--groups integration` to run only
those.

## Known limitations / things to double-check before grading

- **Dual-write consistency**: order status is written to MongoDB and then
  published to Kafka as two separate steps. If the process crashes between
  them, the DB and the event stream disagree (the write succeeds, the event
  never goes out). A transactional outbox would fix this properly; out of
  scope here, but worth a sentence in the report if asked about reliability.
- **`payments.completed` schema is assumed**, not confirmed with the Payment
  Service owner (see above).
- **No auth/authz** on the REST API or between services — fine for a course
  assignment, but flag it if the report asks about production-readiness.
- **Mongo credentials** default to empty (no auth) for local Compose use;
  `mongoUsername`/`mongoPassword` in `Config.toml` are there for a real
  deployment but shouldn't be committed with real values — use a
  non-committed `Config.toml` override or `-Ckey=value` / Docker secrets.
- Ballerina distribution is pinned to `2201.13.5` (bumped from the original
  `2201.9.0`) because `ballerinax/mongodb` and `ballerinax/kafka` both
  require `>= 2201.12.0`. The Dockerfile's runtime stage was bumped from
  `openjdk:17-jdk-slim` to `eclipse-temurin:21-jre-jammy` for the same
  reason (those connectors ship native libraries built for Java 21).
