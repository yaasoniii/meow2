import dsa612s/customer_service.customer;

// ---------- Event payloads consumed from the Order Service ----------
//
// These mirror the shared Kafka contract documented in order-service/README.md
// (Jason owns those topics; the Customer Service only reads them). They are
// declared as OPEN records - `record { }` rather than `record {| |}` - so a
// field the Order Service adds later flows through harmlessly instead of
// failing to deserialise and stalling the consumer.

type OrderCreatedEvent record {
    string orderId;
    string customerId;
    string restaurantId;
    customer:OrderItem[] items;
    decimal totalAmount;
    string timestamp;
};

// Note there is no customerId on this event - it only identifies the order. The
// consumer therefore updates an existing history row and cannot create one; see
// handleStatusUpdated in consumer.bal.
type OrderStatusUpdatedEvent record {
    string orderId;
    string previousStatus;
    string newStatus;
    string timestamp;
};
