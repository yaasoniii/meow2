import ballerina/time;
import ballerinax/kafka;

configurable string restaurantStatusTopic = "restaurant.status";

final kafka:Producer statusProducer = check new (kafkaBootstrapServers, {
    acks: "1"
});

public function publishRestaurantStatus(string restaurantId, string orderId, string status,
        string? reason = ()) returns error? {
    RestaurantStatusEvent event = {
        restaurantId: restaurantId,
        orderId: orderId,
        status: status,
        reason: reason,
        timestamp: time:utcToString(time:utcNow())
    };

    kafka:BytesProducerRecord producerRecord = {
        topic: restaurantStatusTopic,
        // Keyed by orderId like every other topic, so all events for one order
        // land on the same partition and stay in order.
        key: orderId.toBytes(),
        value: event.toJsonString().toBytes()
    };

    check statusProducer->send(producerRecord);
}