import ballerina/log;
import ballerinax/kafka;
import restaurant_service.store;

configurable string kafkaBootstrapServers = "localhost:9092";
configurable string ordersCreatedTopic = "orders.created";
configurable string orderConsumerGroupId = "restaurant-service-group";

// The restaurant(s) this running instance manages. Kept simple for the
// assignment — a real multi-tenant deployment would look this up per
// event instead of hardcoding it here.
configurable string[] managedRestaurantIds = [];

listener kafka:Listener orderListener = new (kafkaBootstrapServers, {
    groupId: orderConsumerGroupId,
    topics: [ordersCreatedTopic],
    offsetReset: "earliest",
    autoCommit: false
});

service on orderListener {

    remote function onConsumerRecord(kafka:Caller caller, OrderCreatedEvent[] events) returns error? {
        foreach OrderCreatedEvent event in events {
            handleOrderCreated(event);
        }
        check caller->commit();
    }
}

function handleOrderCreated(OrderCreatedEvent event) {
    if managedRestaurantIds.length() > 0 && managedRestaurantIds.indexOf(event.restaurantId) is () {
        // Not one of ours — ignore.
        return;
    }

    foreach OrderItemPayload item in event.items {
        boolean|error result = store:decrementStock(event.restaurantId, item.itemId, item.quantity);
        if result is error {
            log:printError("Failed to decrement stock for item " + item.itemId, result);
        } else if !result {
            log:printWarn("Order references item not owned by this restaurant: " + item.itemId);
        }
    }

    error? publishResult = publishRestaurantStatus(event.restaurantId, event.orderId, "ACKNOWLEDGED");
    if publishResult is error {
        log:printError("Failed to publish restaurant.status for order " + event.orderId, publishResult);
    }
}

public function consumedTopics() returns string[] {
    return [ordersCreatedTopic];
}