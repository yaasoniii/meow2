import ballerina/log;
import ballerina/time;
import ballerina/uuid;
import ballerinax/kafka;
import dsa612s/delivery_service.domain;
import dsa612s/delivery_service.store;

configurable string paymentsCompletedTopic = "payments.completed";
configurable string paymentConsumerGroupId = "delivery-service-payment-consumer";

listener kafka:Listener paymentListener = new (kafkaBootstrapServers, {
    groupId: paymentConsumerGroupId,
    topics: [paymentsCompletedTopic],
    offsetReset: kafka:OFFSET_RESET_EARLIEST,
    autoCommit: false
});

service on paymentListener {

    remote function onConsumerRecord(kafka:Caller caller, kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord kafkaRecord in records {
            error? result = handlePaymentCompleted(kafkaRecord);
            if result is error {
                // Log and continue
                log:printError("Failed to process payments.completed record", result);
            }
        }
        // Commit only after the whole batch has been handled.
        kafka:Error? commitResult = caller->commit();
        if commitResult is kafka:Error {
            log:printError("Failed to commit payments.completed offsets", commitResult);
        }
    }
}

isolated function handlePaymentCompleted(kafka:BytesConsumerRecord kafkaRecord) returns error? {
    string payload = check string:fromBytes(kafkaRecord.value);
    PaymentCompletedEvent event = check payload.fromJsonStringWithType(PaymentCompletedEvent);

    if event.status != "SUCCESS" {
    log:printInfo("Ignoring non-successful payment", orderId = event.orderId, status = event.status);
    return;
}

    domain:Delivery? existing = check store:findDeliveryByOrderId(event.orderId);
    if existing is domain:Delivery {
        log:printInfo("Delivery already exists for order, skipping", orderId = event.orderId);
        return;
    }

    string now = time:utcToString(time:utcNow());
    string deliveryId = uuid:createType1AsString();

    domain:Delivery newDelivery = {
        deliveryId: deliveryId,
        orderId: event.orderId,
        status: domain:PENDING,
        createdAt: now
    };
    check store:saveDelivery(newDelivery);
    log:printInfo("Created delivery for paid order", orderId = event.orderId, deliveryId = deliveryId);

    // Try to assign a driver right away.
    domain:Driver[] available = check store:fetchAvailableDrivers();
    domain:Driver? picked = domain:selectAvailableDriver(available);
    if picked is () {
        log:printWarn("No driver available; delivery stays PENDING", deliveryId = deliveryId);
        return;
    }

    check store:applyDeliveryStatusTransition(deliveryId, domain:PENDING, domain:ASSIGNED, now, picked.driverId);
    check store:updateDriverStatus(picked.driverId, domain:ON_DELIVERY, deliveryId);
    check publishDeliveryAssigned(deliveryId, event.orderId, picked.driverId);
    log:printInfo("Assigned driver", deliveryId = deliveryId, driverId = picked.driverId);
}