import ballerina/log;
import ballerina/time;
import ballerinax/kafka;
import restaurant_service.restaurant;
import restaurant_service.store;

configurable string kafkaBootstrapServers = "kafka:9092";
configurable string ordersCreatedTopic = "orders.created";
configurable string orderConsumerGroupId = "restaurant-service-group";

// Opening hours are local kitchen time; containers run in UTC. Namibia is UTC+2.
configurable int localUtcOffsetHours = 2;

// The restaurant(s) this running instance manages. Kept simple for the
// assignment - a real multi-tenant deployment would look this up per
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
            error? result = handleOrderCreated(event);
            if result is error {
                log:printError("Failed to handle orders.created", result, orderId = event.orderId);
            }
        }
        check caller->commit();
    }
}

// Accept (decrement stock, ACKNOWLEDGED) or reject (REJECTED + reason) each new order.
function handleOrderCreated(OrderCreatedEvent event) returns error? {
    if managedRestaurantIds.length() > 0 && managedRestaurantIds.indexOf(event.restaurantId) is () {
        return; // Not one of ours.
    }

    restaurant:Restaurant? owner = check store:findRestaurantById(event.restaurantId);
    if owner is () {
        return reject(event, "Restaurant not found");
    }

    restaurant:MenuItem[] menu = check store:findMenuByRestaurant(event.restaurantId);
    restaurant:OrderLine[] lines = from OrderItemPayload item in event.items
        select {itemId: item.itemId, name: item.name, quantity: item.quantity};
    string? reason = restaurant:rejectionReason(owner, localTimeOfDay(), lines, menu);
    if reason is string {
        return reject(event, reason);
    }

    foreach OrderItemPayload item in event.items {
        if !check store:decrementStock(event.restaurantId, item.itemId, item.quantity) {
            // Only possible if stock was edited between the check above and now.
            log:printWarn("Stock ran out while accepting order", orderId = event.orderId, itemId = item.itemId);
        }
    }
    check publishRestaurantStatus(event.restaurantId, event.orderId, "ACKNOWLEDGED");
    log:printInfo("Accepted order", orderId = event.orderId, restaurantId = event.restaurantId);
}

function reject(OrderCreatedEvent event, string reason) returns error? {
    check publishRestaurantStatus(event.restaurantId, event.orderId, "REJECTED", reason);
    log:printInfo("Rejected order", orderId = event.orderId, reason = reason);
}

function localTimeOfDay() returns string {
    time:Utc local = time:utcAddSeconds(time:utcNow(), <decimal>(localUtcOffsetHours * 3600));
    time:Civil civil = time:utcToCivil(local);
    return string `${civil.hour < 10 ? "0" : ""}${civil.hour}:${civil.minute < 10 ? "0" : ""}${civil.minute}`;
}

public function consumedTopics() returns string[] {
    return [ordersCreatedTopic];
}
