import ballerina/log;
import ballerinax/kafka;
import dsa612s/notification_service.store;

configurable string kafkaBootstrapServers = "kafka:9092";

configurable string ordersCreatedTopic = "orders.created";
configurable string ordersStatusUpdatedTopic = "orders.status_updated";
configurable string paymentsCompletedTopic = "payments.completed";
configurable string restaurantStatusTopic = "restaurant.status";
configurable string deliveryAssignedTopic = "delivery.assigned";
configurable string deliveryCompletedTopic = "delivery.completed";

configurable string notificationConsumerGroupId = "notification-service-consumer";

// Simulated delivery channels per audience. Each send is logged as the stand-in
// for a real email / SMS / push gateway call.
final readonly & map<string[]> channelsFor = {
    CUSTOMER: ["EMAIL", "SMS"],
    RESTAURANT: ["DASHBOARD", "EMAIL"],
    DRIVER: ["PUSH", "SMS"]
};

listener kafka:Listener notificationListener = new (kafkaBootstrapServers, {
    groupId: notificationConsumerGroupId,
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

// Everything needed to send the alerts for one Kafka record.
type Event record {|
    string id; // "<topic>-<partition>-<offset>"
    string topic;
    string orderId;
    string timestamp;
|};

isolated function handleNotificationEvent(kafka:BytesConsumerRecord kafkaRecord) returns error? {
    string topic = kafkaRecord.offset.partition.topic;
    string payload = check string:fromBytes(kafkaRecord.value);
    string id = string `${topic}-${kafkaRecord.offset.partition.partition}-${kafkaRecord.offset.offset}`;

    if topic == ordersCreatedTopic {
        OrderCreatedEvent e = check payload.fromJsonStringWithType(OrderCreatedEvent);
        check store:rememberOrder(e.orderId, {customerId: e.customerId, restaurantId: e.restaurantId});
        Event ev = {id, topic, orderId: e.orderId, timestamp: e.timestamp};
        int count = 0;
        string[] lines = [];
        foreach OrderItemPayload item in e.items {
            count += item.quantity;
            lines.push(string `${item.quantity}x ${item.name}`);
        }
        check notify(ev, store:CUSTOMER, "Order placed",
                string `Your order of ${count} item(s) totalling ${money(e.totalAmount)} was placed.`);
        check notify(ev, store:RESTAURANT, "New order",
                string `Order #${short(e.orderId)}: ${string:'join(", ", ...lines)} (${money(e.totalAmount)}).`);
        return;
    }

    if topic == ordersStatusUpdatedTopic {
        OrderStatusUpdatedEvent e = check payload.fromJsonStringWithType(OrderStatusUpdatedEvent);
        Event ev = {id, topic, orderId: e.orderId, timestamp: e.timestamp};
        [string, string] [title, message] = describeOrderStatus(e.newStatus);
        check notify(ev, store:CUSTOMER, title, message);
        if e.newStatus == "READY" {
            check notify(ev, store:DRIVER, "Ready for pickup",
                    string `Order #${short(e.orderId)} is packed and waiting for you at the restaurant.`);
        } else if e.newStatus == "CANCELLED" {
            check notify(ev, store:RESTAURANT, "Order cancelled",
                    string `Order #${short(e.orderId)} was cancelled - stop preparing it.`);
            check notify(ev, store:DRIVER, "Delivery cancelled",
                    string `Order #${short(e.orderId)} was cancelled - no pickup needed.`);
        } else if e.newStatus == "DELIVERED" {
            check notify(ev, store:RESTAURANT, "Order delivered",
                    string `Order #${short(e.orderId)} reached the customer.`);
        }
        return;
    }

    if topic == paymentsCompletedTopic {
        PaymentCompletedEvent e = check payload.fromJsonStringWithType(PaymentCompletedEvent);
        string? customerId = e?.customerId;
        if customerId is string {
            check store:rememberOrder(e.orderId, {customerId});
        }
        Event ev = {id, topic, orderId: e.orderId, timestamp: e.timestamp};
        decimal? amount = e?.amount;
        string amountText = amount is decimal ? " of " + money(amount) : "";
        if e.status == "SUCCESS" {
            check notify(ev, store:CUSTOMER, "Payment received", string `Your payment${amountText} was successful.`);
            check notify(ev, store:RESTAURANT, "Payment confirmed",
                    string `Order #${short(e.orderId)} is paid - start preparing.`);
        } else if e.status == "REFUNDED" {
            check notify(ev, store:CUSTOMER, "Refund issued",
                    string `Your payment${amountText} has been refunded.`);
        } else {
            check notify(ev, store:CUSTOMER, "Payment failed",
                    string `Your payment${amountText} did not go through. You can retry it from your order.`);
        }
        return;
    }

    if topic == restaurantStatusTopic {
        RestaurantStatusEvent e = check payload.fromJsonStringWithType(RestaurantStatusEvent);
        Event ev = {id, topic, orderId: e.orderId, timestamp: e.timestamp};
        if e.status == "ACKNOWLEDGED" {
            check notify(ev, store:CUSTOMER, "Restaurant accepted", "The restaurant has received your order.");
        } else if e.status == "REJECTED" {
            check notify(ev, store:CUSTOMER, "Order rejected",
                    (e?.reason ?: "The restaurant could not take your order") + ". Any payment will be refunded.");
        }
        return;
    }

    if topic == deliveryAssignedTopic {
        DeliveryAssignedEvent e = check payload.fromJsonStringWithType(DeliveryAssignedEvent);
        check store:rememberOrder(e.orderId, {driverId: e.driverId});
        Event ev = {id, topic, orderId: e.orderId, timestamp: e.timestamp};
        check notify(ev, store:CUSTOMER, "Driver assigned", "A driver has been assigned to deliver your order.");
        check notify(ev, store:DRIVER, "New delivery job",
                string `You have been assigned order #${short(e.orderId)}. Head to the restaurant.`);
        return;
    }

    if topic == deliveryCompletedTopic {
        DeliveryCompletedEvent e = check payload.fromJsonStringWithType(DeliveryCompletedEvent);
        Event ev = {id, topic, orderId: e.orderId, timestamp: e.timestamp};
        check notify(ev, store:DRIVER, "Delivery completed",
                string `Order #${short(e.orderId)} delivered - you are available for the next job.`);
        return;
    }

    log:printWarn("Ignoring event from an unexpected topic", topic = topic);
}

// Stores one notification for `audience` and "sends" it on each of that audience's channels.
isolated function notify(Event ev, store:Audience audience, string title, string message) returns error? {
    store:OrderContext ctx = check store:findOrderContext(ev.orderId);
    string? recipientId = audience == store:CUSTOMER ? ctx?.customerId
        : audience == store:RESTAURANT ? ctx?.restaurantId : ctx?.driverId;
    if audience == store:DRIVER && recipientId is () {
        return; // no driver assigned yet - nobody to tell
    }

    string[] channels = channelsFor[audience] ?: [];
    store:Notification notification = {
        notificationId: ev.id + "-" + audience,
        topic: ev.topic,
        orderId: ev.orderId,
        audience,
        recipientId,
        channels,
        title,
        message,
        timestamp: ev.timestamp
    };
    check store:saveNotification(notification);
    foreach string channel in channels {
        log:printInfo(string `[${channel}] -> ${audience} ${recipientId ?: "?"}: ${title}`, orderId = ev.orderId);
    }
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

isolated function short(string id) returns string {
    return id.length() > 8 ? id.substring(0, 8) : id;
}

// For GET /health, and so service.bal imports this module (which starts the listener).
public isolated function consumedTopics() returns string[] {
    return [ordersCreatedTopic, ordersStatusUpdatedTopic, paymentsCompletedTopic, restaurantStatusTopic,
        deliveryAssignedTopic, deliveryCompletedTopic];
}
