# Notification Service

Owner: Gerson

Turns platform events into readable notifications for customers. In a real deployment these would be sent as email, SMS or push messages. Here they are logged and served over REST.

## Kafka (consumes)

`orders.created`, `orders.status_updated`, `payments.completed`, `restaurant.status`, `delivery.assigned` and `delivery.completed`.

Each event is parsed into its type in `modules/messaging/types.bal` and turned into a `Notification` `{notificationId, topic, orderId, customerId, title, message, timestamp}`. Most events only carry `orderId`. The service remembers `orderId -> customerId` from `orders.created` (and `payments.completed`) so it can address every notification to the right customer.

## REST API (port 8086)

| Method | Path | Description |
|--------|------|-------------|
| GET | /notifications?customerId=&orderId=&limit=50 | Newest first |
| GET | /health | `{status, consumedTopics}` |

## Storage

**In memory for now** (`modules/messaging/inbox.bal`, capped at 1000 entries). The database is planned for later. Until then, every start joins a fresh consumer group and replays all topics from the beginning, which rebuilds the inbox after a restart. Once notifications are persisted, remove the random suffix in `consumer.bal` so committed offsets are used again.
