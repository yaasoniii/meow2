import ballerina/log;
import ballerina/time;
import ballerinax/kafka;

configurable string kafkaBootstrapServers = "kafka:9092";
configurable string deliveryAssignedTopic = "delivery.assigned";
configurable string deliveryCompletedTopic = "delivery.completed";

final kafka:Producer deliveryProducer = check new (kafkaBootstrapServers, {
    clientId: "delivery-service-producer",
    acks: kafka:ACKS_ALL,
    retryCount: 3
});

public isolated function publishDeliveryAssigned(string deliveryId, string orderId, string driverId) returns error?{
    DeliveryAssignedEvent event = {
        deliveryId: deliveryId,
        orderId: orderId,
        driverId: driverId,
        timestamp: time:utcToString(time:utcNow())
    };
    check deliveryProducer->send({
        topic: deliveryAssignedTopic,
        key:  orderId.toBytes(),
        value:  event.toJsonString().toBytes()
    });
    log:printInfo("Published delivery.assigned", deliveryId = deliveryId, orderId = orderId, driveId = driverId);
}

public isolated function pubishDeliveryCompleted(string deliveryId, string orderId, string driverId) returns error? {
    DeliveryCompletedEvent event ={
        deliveryId: deliveryId,
        orderId: orderId,
        driverId: driverId,
        timestamp: time:utcToString(time:utcNow())
    };
    check deliveryProducer->send({
        topic: deliveryCompletedTopic,
        key: orderId.toBytes(),
        value:  event.toJsonString().toBytes()
    });
    log:printInfo("Published delivery.completed", deliveryId = deliveryId, orderId = orderId, driverId = driverId);
}