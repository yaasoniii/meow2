# Restaurant Service

Owner: Renate

Restaurant profiles, opening hours and menus. It also reacts to new orders by reducing stock and acknowledging the order.

## REST API (port 8083)

| Method | Path | Description |
|--------|------|-------------|
| POST   | /restaurants | Register a restaurant `{ownerId, name, description, location, hours:{openTime, closeTime}}` (times `HH:MM`) |
| GET    | /restaurants | List restaurants |
| GET    | /restaurants/{restaurantId} | Fetch one |
| PUT    | /restaurants/{restaurantId} | Update `{name, description, location}` |
| PUT    | /restaurants/{restaurantId}/hours | Update `{openTime, closeTime}` |
| DELETE | /restaurants/{restaurantId} | Delete the restaurant and its menu (404 if unknown) |
| GET    | /restaurants/{restaurantId}/menu | List menu items |
| POST   | /restaurants/{restaurantId}/menu | Add `{name, description, price, stockCount}` (404 if the restaurant doesn't exist) |
| PUT    | /restaurants/{restaurantId}/menu/{itemId} | Partial update `{name?, description?, price?, stockCount?, available?}` |
| DELETE | /restaurants/{restaurantId}/menu/{itemId} | Delete an item (404 if it doesn't belong to that restaurant) |
| GET    | /health | `{status, consumedTopics}` |

Menu item reads, updates and deletes are scoped by **both** `restaurantId` and `itemId`, so one restaurant can't change another restaurant's dishes.

## Kafka

- **Consumes** `orders.created`. For each item it decrements stock, floored at 0, and marks the item unavailable when stock reaches 0. It then publishes an acknowledgement.
- **Produces** `restaurant.status` `{restaurantId, orderId, status: "ACKNOWLEDGED", timestamp}`, keyed by `orderId`. The Order Service uses this to move the order from `CREATED` to `CONFIRMED`.

## Storage

MongoDB database `restaurant_service`, with collections `restaurants` and `menu_items`. Unique indexes on `restaurantId` and `itemId` are created at startup in `modules/store` `init()`.

## Layout

```
service.bal             REST API
modules/restaurant/     types + validation (pure, unit tested)
modules/store/          MongoDB access
modules/messaging/      orders.created consumer, restaurant.status producer
```

## Run / test

```
docker compose up -d --build restaurant-service     # from the repo root
cd restaurant-service && bal test --tests "restaurant_service.restaurant:*"   # pure validation tests
```
