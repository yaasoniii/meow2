# Frontend

A dependency-free web client for the whole platform: plain HTML, CSS and ES modules, with no build step. It is served by nginx, which also proxies the APIs.

## Run

```
docker compose up -d --build     # from the repo root
```

Open http://localhost:3000, then use **System → Load demo data** for a ready-made restaurant, customer and drivers.

## Views

| Tab | Who | What it does | Services used |
|-----|-----|--------------|---------------|
| Customer | customer | Register or sign in, browse restaurants and menus, basket, place an order, **live order tracker** (timeline, payment, driver), retry a failed payment, cancel, notifications inbox, addresses | customer, restaurant, order, payment, delivery, notification |
| Restaurant | restaurant | Register, an order board (incoming → preparing → ready → done), **Mark ready**, menu and stock management | restaurant, order |
| Driver | driver | Register, go online or off shift, current job (where to collect, where to deliver), pickup → trip → delivered | delivery, order, restaurant, customer |
| Admin | admin | Live KPIs, orders-by-status chart, all orders, generate and view reports | admin |
| System | anyone | Health of all 7 services and their consumed topics, the order-flow explanation, a live event stream, demo-data seeding | all |

Every view polls its data every 2.5 s, so progress made by Kafka consumers in other services appears without reloading.

## How it connects

The browser only talks to nginx (`nginx.conf`). Requests to `/api/<service>/<path>` are forwarded to `http://<service>:<port>/<path>` on the Compose network:

| Prefix | Service |
|--------|---------|
| `/api/order/` | order-service:8081 |
| `/api/customer/` | customer-service:8082 |
| `/api/restaurant/` | restaurant-service:8083 |
| `/api/payment/` | payment-service:8084 |
| `/api/delivery/` | delivery-service:8085 |
| `/api/notification/` | notification-service:8086 |
| `/api/admin/` | admin-service:8087 |

Because everything is same-origin, the services need no CORS configuration. Upstreams are resolved per request, so the UI still loads while a service is down. That service's calls return 503, and the System tab shows it as **Down**.

## Files

```
public/index.html        shell + role navigation
public/styles.css        design tokens (light/dark), layout, components
public/js/app.js         hash router + polling loop
public/js/api.js         REST client for every service
public/js/ui.js          rendering helpers (escaping, pills, timeline, toasts)
public/js/views/*.js     one module per tab
```
