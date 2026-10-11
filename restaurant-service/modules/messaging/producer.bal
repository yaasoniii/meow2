import ballerina/time;
import ballerinax/kafka;

configurable string restaurantStatusTopic = "restaurant.status";

final kafka:Producer statusProducer = check new (kafkaBootstrapServers, {
    acks: "1"
});

public function publishRestaurantStatus(string restaurantId, string orderId, string status) returns error? {
    RestaurantStatusEvent event = {
        restaurantId: restaurantId,
        orderId: orderId,
        status: status,
        timestamp: time:utcToString(time:utcNow())
    };

    kafka:BytesProducerRecord producerRecord = {
        topic: restaurantStatusTopic,
        value: event.toJsonString().toBytes()
    };

    check statusProducer->send(producerRecord);
}