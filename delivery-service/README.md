# Delivery Service

Owner: Penny

Manages drivers and deliveries. It assigns a free driver to every paid order and reports delivery progress to the Order Service.

## Delivery lifecycle

```
PENDING -> ASSIGNED -> PICKED_UP -> IN_PROGRESS -> DELIVERED
   \-> CANCELLED  \-> CANCELLED      (no cancelling after pickup)
```

Drivers are `AVAILABLE`, `ON_DELIVERY` or `UNAVAILABLE`.

## REST API (port 8085)

| Method | Path | Description |
|--------|------|-------------|
| POST | /drivers | Register `{name, phoneNumber, plateNumber, vehicleType}`. The driver starts AVAILABLE and may be given a waiting delivery immediately |
| GET  | /drivers | List drivers |
| GET  | /drivers/{driverId} | Fetch one |
| PUT  | /drivers/{driverId}/status | `{status: AVAILABLE \| UNAVAILABLE}`. Returns 409 while the driver is ON_DELIVERY |
| GET  | /deliveries?orderId=&driverId=&status= | List deliveries, newest first |
| GET  | /deliveries/{deliveryId} | Fetch one |
| POST | /deliveries/{deliveryId}/assign | Retry driver assignment for a PENDING delivery |
| PUT  | /deliveries/{deliveryId}/status | `{status}`. Moves along the lifecycle above, or returns 409 for an invalid transition |
| GET  | /health | `{status, consumedTopics}` |

## Kafka

**Consumes**
- `payments.completed`: on `SUCCESS` it creates a PENDING delivery, at most one per order thanks to a unique index on `orderId`. It then tries to assign a driver.
- `orders.status_updated`: on `CANCELLED` it cancels the order's delivery if it hasn't been picked up yet, and frees the driver.

**Produces** (all keyed by `orderId`)
- `delivery.assigned` `{deliveryId, orderId, driverId, timestamp}`
- `delivery.status_updated` `{deliveryId, orderId, driverId, previousStatus, newStatus, timestamp}` on every transition. The Order Service uses `PICKED_UP` and `DELIVERED`.
- `delivery.completed` `{deliveryId, orderId, driverId, timestamp}`

## Driver assignment

- **Atomic claim.** `store:claimDriver` updates the driver with the filter `{driverId, status: AVAILABLE}`. If two deliveries race for the same driver, only one update matches. The loser moves on to the next free driver.
- **Re-assignment.** When a delivery ends, or a driver registers or comes back online, waiting PENDING deliveries are handed out oldest-first.

## Storage

MongoDB database `delivery_service`, with collections `drivers` and `deliveries`.

## Layout

```
service.bal            REST API
modules/domain/        types, transition rules, driver selection, validation (pure, unit tested)
modules/store/         MongoDB access
modules/messaging/     consumer, producer, dispatch (assignment + transitions shared by REST and Kafka)
```

## Test

```
bal test --tests "delivery_service.domain:*"
```
