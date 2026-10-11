import ballerina/log;
import ballerina/time;
import ballerina/uuid;
import ballerinax/kafka;
import dsa612s/delivery_service.domain;
import dsa612s/delivery_service.store;

configurable string paymentsCompletedTopic = "payments.completed";
configurable string ordersStatusUpdatedTopic = "orders.status_updated";
configurable string eventConsumerGroupId = "delivery-service-consumer";

const string PAYMENT_SUCCESS = "SUCCESS";
const string ORDER_CANCELLED = "CANCELLED";

listener kafka:Listener eventListener = new (kafkaBootstrapServers, {
    groupId: eventConsumerGroupId,
    topics: [paymentsCompletedTopic, ordersStatusUpdatedTopic],
    offsetReset: kafka:OFFSET_RESET_EARLIEST,
    autoCommit: false
});

service on eventListener {

    remote function onConsumerRecord(kafka:Caller caller, kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord kafkaRecord in records {
            error? result = handleRecord(kafkaRecord);
            if result is error {
                // Log and continue: one bad record shouldn't block the rest of the batch.
                log:printError("Failed to process event", result, topic = kafkaRecord.offset.partition.topic);
            }
        }
        // Commit only after the whole batch has been handled.
        kafka:Error? commitResult = caller->commit();
        if commitResult is kafka:Error {
            log:printError("Failed to commit offsets", commitResult);
        }
    }
}

isolated function handleRecord(kafka:BytesConsumerRecord kafkaRecord) returns error? {
    string topic = kafkaRecord.offset.partition.topic;
    string payload = check string:fromBytes(kafkaRecord.value);
    if topic == paymentsCompletedTopic {
        return handlePaymentCompleted(payload);
    }
    if topic == ordersStatusUpdatedTopic {
        return handleOrderStatusUpdated(payload);
    }
    log:printWarn("Ignoring event from an unexpected topic", topic = topic);
}

// A paid order gets a delivery, and a driver straight away if one is free.
isolated function handlePaymentCompleted(string payload) returns error? {
    PaymentCompletedEvent event = check payload.fromJsonStringWithType(PaymentCompletedEvent);

    if event.status != PAYMENT_SUCCESS {
        log:printInfo("Ignoring non-successful payment", orderId = event.orderId, status = event.status);
        return;
    }

    domain:Delivery? existing = check store:findDeliveryByOrderId(event.orderId);
    if existing is domain:Delivery {
        log:printInfo("Delivery already exists for order, skipping", orderId = event.orderId);
        return;
    }

    domain:Delivery newDelivery = {
        deliveryId: uuid:createType1AsString(),
        orderId: event.orderId,
        status: domain:PENDING,
        createdAt: time:utcToString(time:utcNow())
    };
    check store:saveDelivery(newDelivery);
    log:printInfo("Created delivery for paid order", orderId = event.orderId, deliveryId = newDelivery.deliveryId);

    if !check tryAssignDriver(newDelivery) {
        log:printWarn("No driver available; delivery stays PENDING", deliveryId = newDelivery.deliveryId);
    }
}

// A cancelled order cancels its delivery if no driver has picked it up yet.
isolated function handleOrderStatusUpdated(string payload) returns error? {
    OrderStatusUpdatedEvent event = check payload.fromJsonStringWithType(OrderStatusUpdatedEvent);
    if event.newStatus != ORDER_CANCELLED {
        return;
    }

    domain:Delivery? existing = check store:findDeliveryByOrderId(event.orderId);
    if existing is () || !domain:isValidDeliveryStatusTransition(existing.status, domain:CANCELLED) {
        return;
    }
    _ = check transitionDelivery(existing, domain:CANCELLED);
    log:printInfo("Cancelled delivery for cancelled order", orderId = event.orderId);
}

// For GET /health, and so service.bal imports this module (which is what starts the listener).
public isolated function consumedTopics() returns string[] {
    return [paymentsCompletedTopic, ordersStatusUpdatedTopic];
}
