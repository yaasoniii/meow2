import ballerina/log;
import ballerina/time;
import ballerinax/kafka;
import dsa612s/order_service.lifecycle;

configurable string kafkaBootstrapServers = "kafka:9092";

// ---------- Kafka topics (shared contract for the whole platform) ----------
const string TOPIC_ORDERS_CREATED = "orders.created";
const string TOPIC_ORDERS_STATUS_UPDATED = "orders.status_updated";

final kafka:Producer orderProducer = check new (kafkaBootstrapServers, {
    clientId: "order-service-producer",
    acks: "all",
    retryCount: 3
});

public isolated function publishOrderCreated(lifecycle:Order 'order) returns error? {
    OrderCreatedEvent event = {
        orderId: 'order.orderId,
        customerId: 'order.customerId,
        restaurantId: 'order.restaurantId,
        items: 'order.items,
        totalAmount: 'order.totalAmount,
        timestamp: time:utcToString(time:utcNow())
    };
    check orderProducer->send({
        topic: TOPIC_ORDERS_CREATED,
        key: 'order.orderId.toBytes(),
        value: event.toJsonString().toBytes()
    });
    log:printInfo("Published orders.created", orderId = 'order.orderId);
}

public isolated function publishStatusUpdated(string orderId, lifecycle:OrderStatus previous,
        lifecycle:OrderStatus current) returns error? {
    OrderStatusUpdatedEvent event = {
        orderId: orderId,
        previousStatus: previous,
        newStatus: current,
        timestamp: time:utcToString(time:utcNow())
    };
    check orderProducer->send({
        topic: TOPIC_ORDERS_STATUS_UPDATED,
        key: orderId.toBytes(),
        value: event.toJsonString().toBytes()
    });
    log:printInfo("Published orders.status_updated", orderId = orderId, newStatus = current);
}
