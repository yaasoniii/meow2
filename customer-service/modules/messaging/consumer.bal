import ballerina/log;
import ballerinax/kafka;
import dsa612s/customer_service.customer;
import dsa612s/customer_service.store;

configurable string kafkaBootstrapServers = "kafka:9092";
configurable string ordersCreatedTopic = "orders.created";
configurable string ordersStatusUpdatedTopic = "orders.status_updated";
configurable string orderConsumerGroupId = "customer-service-order-consumer";

// One listener subscribed to both topics rather than two listeners: they carry
// the same partition key (orderId), so a single consumer keeps every event for
// one order in the order it was produced - orders.created is guaranteed to be
// handled before the status updates that follow it.
//
// autoCommit is off so an offset is only committed after the batch has actually
// been written to Mongo; a crash mid-batch replays it instead of losing it.
listener kafka:Listener orderListener = new (kafkaBootstrapServers, {
    groupId: orderConsumerGroupId,
    topics: [ordersCreatedTopic, ordersStatusUpdatedTopic],
    offsetReset: "earliest",
    autoCommit: false
});

service on orderListener {

    remote function onConsumerRecord(kafka:Caller caller, kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord kafkaRecord in records {
            error? result = handleOrderRecord(kafkaRecord);
            if result is error {
                // Log and move on rather than failing the whole batch: a single
                // bad/unexpected record shouldn't block the offset commit for
                // the records around it.
                log:printError("Failed to process order event", result,
                        topic = kafkaRecord.offset.partition.topic);
            }
        }

        kafka:Error? commitResult = caller->commit();
        if commitResult is kafka:Error {
            log:printError("Failed to commit order event offsets", commitResult);
        }
    }
}

isolated function handleOrderRecord(kafka:BytesConsumerRecord kafkaRecord) returns error? {
    string topic = kafkaRecord.offset.partition.topic;
    string payload = check string:fromBytes(kafkaRecord.value);

    if topic == ordersCreatedTopic {
        return handleOrderCreated(payload);
    }
    if topic == ordersStatusUpdatedTopic {
        return handleStatusUpdated(payload);
    }
    log:printWarn("Ignoring event from an unexpected topic", topic = topic);
}

isolated function handleOrderCreated(string payload) returns error? {
    OrderCreatedEvent event = check payload.fromJsonStringWithType(OrderCreatedEvent);

    customer:Customer? existing = check store:findCustomerById(event.customerId);
    if existing is () {
        // Recorded anyway. The Order Service doesn't ask us to validate the
        // customer before it accepts an order, so refusing to store the history
        // here would silently lose it if a customer registers afterwards.
        log:printWarn("orders.created for a customer that isn't registered here",
                customerId = event.customerId, orderId = event.orderId);
    }

    customer:OrderHistoryEntry entry = {
        orderId: event.orderId,
        customerId: event.customerId,
        restaurantId: event.restaurantId,
        items: event.items,
        totalAmount: event.totalAmount,
        // orders.created is only ever produced for a brand-new order, so its
        // status at this point is CREATED by definition.
        status: "CREATED",
        placedAt: event.timestamp,
        updatedAt: event.timestamp
    };

    check store:upsertOrderHistory(entry);
    log:printInfo("Recorded order in customer history",
            customerId = event.customerId, orderId = event.orderId);
}

isolated function handleStatusUpdated(string payload) returns error? {
    OrderStatusUpdatedEvent event = check payload.fromJsonStringWithType(OrderStatusUpdatedEvent);

    // The event's own timestamp is used as updatedAt rather than "now": it is
    // when the transition actually happened, which stays correct even if this
    // service was down and is catching up on a backlog.
    boolean updated = check store:updateOrderHistoryStatus(event.orderId, event.newStatus, event.timestamp);
    if !updated {
        // No customerId on this event, so there is nothing to create a history
        // row from. Happens for orders placed before this service first ran.
        log:printWarn("orders.status_updated for an order that isn't in history",
                orderId = event.orderId, newStatus = event.newStatus);
        return;
    }

    log:printInfo("Updated order status in customer history",
            orderId = event.orderId, previousStatus = event.previousStatus, newStatus = event.newStatus);
}

// Exposed so the REST layer can report what this service is wired up to consume
// (see GET /health). It also gives service.bal a real reason to import this
// module, which is what pulls the listener above into the executable and starts
// it - an unimported module is never initialised.
public isolated function consumedTopics() returns string[] {
    return [ordersCreatedTopic, ordersStatusUpdatedTopic];
}
