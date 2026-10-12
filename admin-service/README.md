# Admin Service

Owner: Celine

Platform-wide reporting. It builds its own read model of every order from Kafka events and serves live statistics and saved reports.

## Kafka (consumes)

| Topic | What is recorded on the order |
|-------|-------------------------------|
| `orders.created` | restaurantId, customerId, totalAmount, createdAt, status `CREATED` (only if not already set) |
| `orders.status_updated` | status, updatedAt; plus deliveredAt / cancelledAt |
| `payments.completed` | paymentStatus (`SUCCESS` / `FAILED`) |
| `delivery.assigned` | driverId |
| `delivery.completed` | deliveredAt |

Every event upserts one document per `orderId`. Topics aren't ordered relative to each other, so events can arrive in any order and still end up correct.

## REST API (port 8087)

| Method | Path | Description |
|--------|------|-------------|
| GET  | /admin/health | `{status, consumedTopics}` |
| GET  | /admin/orders | Every order, newest first |
| GET  | /admin/stats | Live totals: orders by status, active orders, delivered revenue, average order value, payment success and failure counts, deliveries, average delivery time |
| POST | /admin/reports | Snapshot a report (per-restaurant totals, delivery times, cancellation rate) and save it |
| GET  | /admin/reports | All saved reports |
| GET  | /admin/reports/{reportId} | One report |

## Storage

MongoDB database `admin_service`, with collections `orders` and `reports`.

## Test

`tests/reports_test.bal` unit-tests `buildReport` and `buildStats`. The package initialises its Mongo connection at startup, so start Mongo first. `tests/Config.toml` points at `localhost`.

```
docker compose up -d mongo kafka
bal test
```
