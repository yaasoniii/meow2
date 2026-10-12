# Notification Service

Owner: Gerson

Turns platform events into alerts for **customers, restaurants and drivers**, over several (simulated) channels:

| Audience | Channels | Example alerts |
|----------|----------|----------------|
| Customer | email + SMS | order placed, accepted or rejected, payment received, failed or refunded, driver assigned, each status change |
| Restaurant | dashboard + email | new order, payment confirmed (start preparing), order cancelled, order delivered |
| Driver | push + SMS | new delivery job, order ready for pickup, delivery cancelled, delivery completed |

Each send is logged as `[CHANNEL] -> AUDIENCE <id>: title`, as a stand-in for a real email, SMS or push gateway call, and stored in MongoDB.

## Kafka (consumes)

`orders.created`, `orders.status_updated`, `payments.completed`, `restaurant.status`, `delivery.assigned` and `delivery.completed`.

## REST API (port 8086)

| Method | Path | Description |
|--------|------|-------------|
| GET | /notifications?recipientId=&audience=&orderId=&limit=50 | Newest first. `audience` is CUSTOMER, RESTAURANT or DRIVER; `limit` is 1-500 |
| GET | /health | `{status, consumedTopics}` |

## Storage

MongoDB database `notification_service`:

- `notifications`: one document per alert per recipient. `notificationId` is `<topic>-<partition>-<offset>-<audience>`, used as the upsert key, so a redelivered event never creates duplicates.
- `order_contexts`: `orderId -> customerId, restaurantId, driverId`, assembled from events. Most events only carry `orderId`; this collection is how alerts reach the right people.

Indexes are created at startup in `modules/store`. See [DATABASE.md](../DATABASE.md).
