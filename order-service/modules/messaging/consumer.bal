import ballerina/log;
import ballerina/time;
import ballerinax/kafka;
import dsa612s/order_service.lifecycle;
import dsa612s/order_service.store;

configurable string paymentsCompletedTopic = "payments.completed";
configurable string restaurantStatusTopic = "restaurant.status";
configurable string deliveryStatusUpdatedTopic = "delivery.status_updated";
configurable string eventConsumerGroupId = "order-service-event-consumer";

// Agreed payments.completed / restaurant.status / delivery values.
const string PAYMENT_SUCCESS = "SUCCESS";
const string RESTAURANT_ACKNOWLEDGED = "ACKNOWLEDGED";
const string RESTAURANT_REJECTED = "REJECTED";
const string DELIVERY_PICKED_UP = "PICKED_UP";
const string DELIVERY_DELIVERED = "DELIVERED";

// One listener for every topic that moves an order forward. Records are handled
// one at a time, so a restaurant ACK and a payment confirmation for the same
// order can never race each other inside this service.
listener kafka:Listener eventListener = new (kafkaBootstrapServers, {
    groupId: eventConsumerGroupId,
    topics: [paymentsCompletedTopic, restaurantStatusTopic, deliveryStatusUpdatedTopic],
    offsetReset: "earliest",
    autoCommit: false
});

service on eventListener {

    remote function onConsumerRecord(kafka:Caller caller, kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord kafkaRecord in records {
            error? result = handleEventRecord(kafkaRecord);
            if result is error {
                // Log and move on rather than failing the whole batch: a single bad/unexpected
                // record shouldn't block the offset commit for the records around it.
                log:printError("Failed to process event", result, topic = kafkaRecord.offset.partition.topic);
            }
        }

        kafka:Error? commitResult = caller->commit();
        if commitResult is kafka:Error {
            log:printError("Failed to commit event offsets", commitResult);
        }
    }
}

isolated function handleEventRecord(kafka:BytesConsumerRecord kafkaRecord) returns error? {
    string topic = kafkaRecord.offset.partition.topic;
    string payload = check string:fromBytes(kafkaRecord.value);

    if topic == paymentsCompletedTopic {
        return handlePaymentCompleted(payload);
    }
    if topic == restaurantStatusTopic {
        return handleRestaurantStatus(payload);
    }
    if topic == deliveryStatusUpdatedTopic {
        return handleDeliveryStatusUpdated(payload);
    }
    log:printWarn("Ignoring event from an unexpected topic", topic = topic);
}

// CREATED -> CONFIRMED needs the restaurant's ACK; CONFIRMED -> PREPARING needs a
// successful payment. The two events can arrive in either order, so the payment
// outcome is stored on the order and whichever event arrives second advances it.
isolated function handlePaymentCompleted(string payload) returns error? {
    PaymentCompletedEvent event = check payload.fromJsonStringWithType(PaymentCompletedEvent);

    lifecycle:Order? existing = check store:findOrderById(event.orderId);
    if existing is () {
        log:printWarn("Received payments.completed for unknown order", orderId = event.orderId);
        return;
    }

    check store:setPaymentStatus(event.orderId, event.status, time:utcToString(time:utcNow()));

    if event.status != PAYMENT_SUCCESS {
        log:printInfo("Payment did not succeed, order stays put", orderId = event.orderId, status = event.status);
        return;
    }

    if existing.status == lifecycle:CONFIRMED {
        check advance(event.orderId, lifecycle:CONFIRMED, lifecycle:PREPARING);
        return;
    }
    // CREATED: the restaurant hasn't acknowledged yet - its ACK will advance the order.
    // Anything later: already moved on (manually, or a redelivered event), so skip.
    log:printInfo("Payment recorded, not advancing", orderId = event.orderId, currentStatus = existing.status);
}

isolated function handleRestaurantStatus(string payload) returns error? {
    RestaurantStatusEvent event = check payload.fromJsonStringWithType(RestaurantStatusEvent);

    lifecycle:Order? existing = check store:findOrderById(event.orderId);
    if existing is () {
        log:printWarn("Received restaurant.status for unknown order", orderId = event.orderId);
        return;
    }

    if event.status == RESTAURANT_REJECTED {
        // The kitchen can't fulfil it (closed, out of stock, ...). Cancelling publishes
        // orders.status_updated, which triggers the refund and cancels any delivery.
        if existing.status != lifecycle:CREATED && existing.status != lifecycle:CONFIRMED {
            log:printInfo("Ignoring rejection, order already in progress", orderId = event.orderId,
                    currentStatus = existing.status);
            return;
        }
        string reason = event?.reason ?: "Rejected by the restaurant";
        check store:setCancellationReason(event.orderId, reason);
        check advance(event.orderId, existing.status, lifecycle:CANCELLED);
        return;
    }

    if event.status != RESTAURANT_ACKNOWLEDGED {
        log:printInfo("Ignoring restaurant status", orderId = event.orderId, status = event.status);
        return;
    }
    if existing.status != lifecycle:CREATED {
        log:printInfo("Skipping restaurant ACK, order is not CREATED", orderId = event.orderId,
                currentStatus = existing.status);
        return;
    }

    check advance(event.orderId, lifecycle:CREATED, lifecycle:CONFIRMED);

    // Payment may already have been confirmed while the order was still CREATED.
    if existing?.paymentStatus == PAYMENT_SUCCESS {
        check advance(event.orderId, lifecycle:CONFIRMED, lifecycle:PREPARING);
    }
}

isolated function handleDeliveryStatusUpdated(string payload) returns error? {
    DeliveryStatusUpdatedEvent event = check payload.fromJsonStringWithType(DeliveryStatusUpdatedEvent);
    if event.newStatus != DELIVERY_PICKED_UP && event.newStatus != DELIVERY_DELIVERED {
        return;
    }

    lifecycle:Order? existing = check store:findOrderById(event.orderId);
    if existing is () {
        log:printWarn("Received delivery.status_updated for unknown order", orderId = event.orderId);
        return;
    }

    lifecycle:OrderStatus current = existing.status;
    if event.newStatus == DELIVERY_PICKED_UP {
        if current == lifecycle:READY {
            check advance(event.orderId, lifecycle:READY, lifecycle:OUT_FOR_DELIVERY);
        } else {
            log:printWarn("Driver picked up an order that is not READY", orderId = event.orderId,
                    currentStatus = current);
        }
        return;
    }

    // DELIVERED. If the pick-up step was skipped, catch up through OUT_FOR_DELIVERY
    // so the order still ends in DELIVERED via legal transitions only.
    if current == lifecycle:READY {
        check advance(event.orderId, lifecycle:READY, lifecycle:OUT_FOR_DELIVERY);
        current = lifecycle:OUT_FOR_DELIVERY;
    }
    if current == lifecycle:OUT_FOR_DELIVERY {
        check advance(event.orderId, lifecycle:OUT_FOR_DELIVERY, lifecycle:DELIVERED);
    } else {
        log:printWarn("Delivery completed for an order that is not out for delivery", orderId = event.orderId,
                currentStatus = current);
    }
}

isolated function advance(string orderId, lifecycle:OrderStatus previous, lifecycle:OrderStatus next) returns error? {
    check store:applyStatusTransition(orderId, previous, next, time:utcToString(time:utcNow()));
    check publishStatusUpdated(orderId, previous, next);
    log:printInfo("Auto-advanced order", orderId = orderId, previousStatus = previous, newStatus = next);
}

// Lets service.bal report what this module consumes (GET /health), and gives it a
// reason to import this module - an unimported module's listener never starts.
public isolated function consumedTopics() returns string[] {
    return [paymentsCompletedTopic, restaurantStatusTopic, deliveryStatusUpdatedTopic];
}
