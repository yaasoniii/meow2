// ------------ Event payloads published to Kafka -----------

type DeliveryAssignedEvent record {|
    string deliveryId;
    string orderId;
    string driverId;
    string timestamp;
|};

type DeliveryCompletedEvent record {|
    string deliveryId;
    string orderId;
    string driverId;
    string timestamp;
|};

// Published on every delivery transition. The Order Service uses PICKED_UP and
// DELIVERED to move the order to OUT_FOR_DELIVERY / DELIVERED.
type DeliveryStatusUpdatedEvent record {|
    string deliveryId;
    string orderId;
    string? driverId;
    string previousStatus;
    string newStatus;
    string timestamp;
|};

// ------------ Event payloads consumed from Kafka (open records) -----------

type PaymentCompletedEvent record {
    string orderId;
    string status;
    string paymentId?;
    string timestamp?;
};

type OrderStatusUpdatedEvent record {
    string orderId;
    string newStatus;
};
