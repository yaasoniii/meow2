import ballerina/log;
import ballerina/uuid;
import ballerinax/kafka;

configurable string kafkaBootstrapServers = "kafka:9092";

configurable string ordersCreatedTopic = "orders.created";
configurable string ordersStatusUpdatedTopic = "orders.status_updated";
configurable string paymentsCompletedTopic = "payments.completed";
configurable string restaurantStatusTopic = "restaurant.status";
configurable string deliveryAssignedTopic = "delivery.assigned";
configurable string deliveryCompletedTopic = "delivery.completed";

configurable string notificationConsumerGroupId = "notification-service-consumer";

// Notifications are only held in memory for now, so each run joins a fresh
// consumer group and reads every topic from the beginning - that rebuilds the
// inbox after a restart. Once notifications are persisted, drop the suffix so
// the group's committed offsets are used again.
final string consumerGroupId = notificationConsumerGroupId + "-" + uuid:createType4AsString();

listener kafka:Listener notificationListener = new (kafkaBootstrapServers, {
    groupId: consumerGroupId,
    topics: [
        ordersCreatedTopic,
        ordersStatusUpdatedTopic,
        paymentsCompletedTopic,
        restaurantStatusTopic,
        deliveryAssignedTopic,
        deliveryCompletedTopic
    ],
    offsetReset: "earliest",
    autoCommit: false
});

service on notificationListener {

    remote function onConsumerRecord(kafka:Caller caller, kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord kafkaRecord in records {
            error? result = handleNotificationEvent(kafkaRecord);
            if result is error {
                log:printError("Failed to process notification event", result,
                        topic = kafkaRecord.offset.partition.topic);
            }
        }

        kafka:Error? commitResult = caller->commit();
        if commitResult is kafka:Error {
            log:printError("Failed to commit notification event offsets", commitResult);
        }
    }
}

isolated function handleNotificationEvent(kafka:BytesConsumerRecord kafkaRecord) returns error? {
    string topic = kafkaRecord.offset.partition.topic;
    string payload = check string:fromBytes(kafkaRecord.value);

    if topic == ordersCreatedTopic {
        OrderCreatedEvent event = check payload.fromJsonStringWithType(OrderCreatedEvent);
        rememberCustomer(event.orderId, event.customerId);
        int itemCount = 0;
        foreach OrderItemPayload item in event.items {
            itemCount += item.quantity;
        }
        notify(topic, event.orderId, event.timestamp, "Order placed",
                string `Your order of ${itemCount} item(s) totalling ${money(event.totalAmount)} was placed.`);
        return;
    }

    if topic == ordersStatusUpdatedTopic {
        OrderStatusUpdatedEvent event = check payload.fromJsonStringWithType(OrderStatusUpdatedEvent);
        [string, string] [title, message] = describeOrderStatus(event.newStatus);
        notify(topic, event.orderId, event.timestamp, title, message);
        return;
    }

    if topic == paymentsCompletedTopic {
        PaymentCompletedEvent event = check payload.fromJsonStringWithType(PaymentCompletedEvent);
        string? customerId = event?.customerId;
        if customerId is string {
            rememberCustomer(event.orderId, customerId);
        }
        decimal? amount = event?.amount;
        string amountText = amount is decimal ? " of " + money(amount) : "";
        if event.status == "SUCCESS" {
            notify(topic, event.orderId, event.timestamp, "Payment received",
                    string `Your payment${amountText} was successful.`);
        } else {
            notify(topic, event.orderId, event.timestamp, "Payment failed",
                    string `Your payment${amountText} did not go through. You can retry it from your order.`);
        }
        return;
    }

    if topic == restaurantStatusTopic {
        RestaurantStatusEvent event = check payload.fromJsonStringWithType(RestaurantStatusEvent);
        if event.status == "ACKNOWLEDGED" {
            notify(topic, event.orderId, event.timestamp, "Restaurant accepted",
                    "The restaurant has received your order.");
        } else {
            notify(topic, event.orderId, event.timestamp, "Restaurant update",
                    "Restaurant status: " + event.status);
        }
        return;
    }

    if topic == deliveryAssignedTopic {
        DeliveryAssignedEvent event = check payload.fromJsonStringWithType(DeliveryAssignedEvent);
        notify(topic, event.orderId, event.timestamp, "Driver assigned",
                "A driver has been assigned to deliver your order.");
        return;
    }

    if topic == deliveryCompletedTopic {
        DeliveryCompletedEvent event = check payload.fromJsonStringWithType(DeliveryCompletedEvent);
        notify(topic, event.orderId, event.timestamp, "Delivery completed",
                "Your driver has marked the order as delivered.");
        return;
    }

    log:printWarn("Ignoring event from an unexpected topic", topic = topic);
}

isolated function notify(string topic, string orderId, string timestamp, string title, string message) {
    Notification notification = {
        notificationId: uuid:createType4AsString(),
        topic: topic,
        orderId: orderId,
        customerId: customerFor(orderId),
        title: title,
        message: message,
        timestamp: timestamp
    };
    addNotification(notification);
    // Stand-in for sending an email/SMS/push.
    log:printInfo("Notification", title = title, orderId = orderId, customerId = notification.customerId);
}

isolated function describeOrderStatus(string status) returns [string, string] {
    match status {
        "CONFIRMED" => {
            return ["Order confirmed", "Your order has been confirmed."];
        }
        "PREPARING" => {
            return ["Being prepared", "The kitchen is preparing your food."];
        }
        "READY" => {
            return ["Ready for pickup", "Your food is ready and waiting for the driver."];
        }
        "OUT_FOR_DELIVERY" => {
            return ["On its way", "Your driver has picked up your order."];
        }
        "DELIVERED" => {
            return ["Delivered", "Your order has been delivered. Enjoy!"];
        }
        "CANCELLED" => {
            return ["Order cancelled", "Your order has been cancelled."];
        }
    }
    return ["Order update", "Your order is now " + status + "."];
}

isolated function money(decimal amount) returns string {
    return "N$" + amount.round(2).toString();
}

// For GET /health, and so service.bal imports this module (which starts the listener).
public isolated function consumedTopics() returns string[] {
    return [ordersCreatedTopic, ordersStatusUpdatedTopic, paymentsCompletedTopic, restaurantStatusTopic,
        deliveryAssignedTopic, deliveryCompletedTopic];
}
