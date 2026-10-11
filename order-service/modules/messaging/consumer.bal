import ballerina/log;
import ballerina/time;
import ballerinax/kafka;
import dsa612s/order_service.lifecycle;
import dsa612s/order_service.store;

configurable string paymentsCompletedTopic = "payments.completed";
configurable string paymentConsumerGroupId = "order-service-payment-consumer";

listener kafka:Listener paymentListener = new (kafkaBootstrapServers, {
    groupId: paymentConsumerGroupId,
    topics: [paymentsCompletedTopic],
    offsetReset: "earliest",
    autoCommit: false
});

service on paymentListener {

    remote function onConsumerRecord(kafka:Caller caller, kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord kafkaRecord in records {
            error? result = handlePaymentCompletedRecord(kafkaRecord);
            if result is error {
                // Log and move on rather than failing the whole batch: a single bad/unexpected
                // record shouldn't block the offset commit for the records around it.
                log:printError("Failed to process payments.completed record", result);
            }
        }

        kafka:Error? commitResult = caller->commit();
        if commitResult is kafka:Error {
            log:printError("Failed to commit payments.completed offsets", commitResult);
        }
    }
}

isolated function handlePaymentCompletedRecord(kafka:BytesConsumerRecord kafkaRecord) returns error? {
    string payload = check string:fromBytes(kafkaRecord.value);
    PaymentCompletedEvent event = check payload.fromJsonStringWithType(PaymentCompletedEvent);

    if event.status != "COMPLETED" {
        log:printInfo("Ignoring non-completed payment event", orderId = event.orderId, status = event.status);
        return;
    }

    lifecycle:Order? existing = check store:findOrderById(event.orderId);
    if existing is () {
        log:printWarn("Received payments.completed for unknown order", orderId = event.orderId);
        return;
    }

    lifecycle:Order current = existing;
    if current.status != lifecycle:CONFIRMED {
        // Already advanced (e.g. by a manual status update) or arrived out of order -
        // auto-advance only applies to the CONFIRMED -> PREPARING step, so skip silently.
        log:printInfo("Skipping auto-transition, order is not CONFIRMED", orderId = event.orderId,
                currentStatus = current.status);
        return;
    }

    string now = time:utcToString(time:utcNow());
    check store:applyStatusTransition(event.orderId, lifecycle:CONFIRMED, lifecycle:PREPARING, now);
    check publishStatusUpdated(event.orderId, lifecycle:CONFIRMED, lifecycle:PREPARING);
    log:printInfo("Auto-advanced order to PREPARING after payment confirmation", orderId = event.orderId);
}
