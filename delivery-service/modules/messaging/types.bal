// ------------ Event payloads publishes to Kafka -----------

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

type PaymentCompletedEvent record {
    string orderId;
    string paymentId;
    string status;
    string timestamp;
};