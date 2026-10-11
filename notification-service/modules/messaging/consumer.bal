import ballerina/log;
import ballerinax/kafka;

configurable string kafkaBootstrapServers = "kafka:9092";

configurable string ordersCreatedTopic = "orders.created";
configurable string ordersStatusUpdatedTopic = "orders.status_updated";
configurable string paymentsCompletedTopic = "payments.completed";
configurable string deliveryAssignedTopic = "delivery.assigned";
configurable string deliveryCompletedTopic = "delivery.completed";

configurable string notificationConsumerGroupId =
    "notification-service-consumer";

listener kafka:Listener notificationListener = new (kafkaBootstrapServers, {
    groupId: notificationConsumerGroupId,
    topics: [
        ordersCreatedTopic,
        ordersStatusUpdatedTopic,
        paymentsCompletedTopic,
        deliveryAssignedTopic,
        deliveryCompletedTopic
    ],
    offsetReset: "earliest",
    autoCommit: false
});

service on notificationListener {

    remote function onConsumerRecord(
        kafka:Caller caller,
        kafka:BytesConsumerRecord[] records
    ) returns error? {

        foreach kafka:BytesConsumerRecord kafkaRecord in records {
            error? result = handleNotificationEvent(kafkaRecord);

            if result is error {
                log:printError(
                    "Failed to process notification event",
                    result
                );
            }
        }

        kafka:Error? commitResult = caller->commit();

        if commitResult is kafka:Error {
            log:printError(
                "Failed to commit notification event offsets",
                commitResult
            );
        }
    }
}

isolated function handleNotificationEvent(
    kafka:BytesConsumerRecord kafkaRecord
) returns error? {

    string topic = kafkaRecord.offset.partition.topic;
    string payload = check string:fromBytes(kafkaRecord.value);

    if topic == ordersCreatedTopic {
        log:printInfo(
            "Received orders.created event",
            payload = payload
        );
        return;
    }

    if topic == ordersStatusUpdatedTopic {
        log:printInfo(
            "Received orders.status_updated event",
            payload = payload
        );
        return;
    }

    if topic == paymentsCompletedTopic {
        log:printInfo(
            "Received payments.completed event",
            payload = payload
        );
        return;
    }

    if topic == deliveryAssignedTopic {
        log:printInfo(
            "Received delivery.assigned event",
            payload = payload
        );
        return;
    }

    if topic == deliveryCompletedTopic {
        log:printInfo(
            "Received delivery.completed event",
            payload = payload
        );
        return;
    }

    log:printWarn(
        "Ignoring event from an unexpected topic",
        topic = topic
    );
}