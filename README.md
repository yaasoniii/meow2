# DSA612S — Distributed Food Delivery Platform

Group assignment: a set of microservices communicating over Kafka, run together with Docker Compose.

## Repo layout

| Folder                  | Service               | Status          |
|-------------------------|-----------------------|-----------------|
| `order-service/`        | Order Service         | Implemented — see its [README](order-service/README.md) |
| `customer-service/`     | Customer Service      | Implemented     |
| `restaurant-service/`   | Restaurant Service    | Started         |
| `payment-service/`      | Payment Service       | Not yet started |
| `delivery-service/`     | Delivery Service      | Not yet started |
| `notification-service/` | Notification Service  | Not yet started |
| `admin-service/`        | Admin Service         | Not yet started |

Each service lives in its own folder with its own `Dockerfile`, and is added to the root `docker-compose.yml` with `build: ./<service-folder>`.

## Running

```
docker compose up -d --build
```
