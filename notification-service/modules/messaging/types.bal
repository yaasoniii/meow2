// ---------- Event payloads consumed from Kafka ----------
// Open records: fields a producing service adds later are ignored, not fatal.

// Event received when a new order is created.
public type OrderCreatedEvent record {
    string orderId;
    string customerId;
    string restaurantId;
    OrderItemPayload[] items;
    decimal totalAmount;
    string timestamp;
};

public type OrderItemPayload record {
    string itemId;
    string name;
    int quantity;
    decimal unitPrice;
};

// Event received when an order moves to another status.
public type OrderStatusUpdatedEvent record {
    string orderId;
    string previousStatus;
    string newStatus;
    string timestamp;
};

// Event received when payment processing is completed ("SUCCESS" / "FAILED").
public type PaymentCompletedEvent record {
    string orderId;
    string paymentId;
    string status;
    string timestamp;
    string customerId?;
    decimal amount?;
};

// Event received when the restaurant reacts to an order (e.g. "ACKNOWLEDGED").
public type RestaurantStatusEvent record {
    string orderId;
    string restaurantId;
    string status;
    string timestamp;
};

// Event received when a driver is assigned.
public type DeliveryAssignedEvent record {
    string deliveryId;
    string orderId;
    string driverId;
    string timestamp;
};

// Event received when a delivery is completed.
public type DeliveryCompletedEvent record {
    string deliveryId;
    string orderId;
    string driverId;
    string timestamp;
};

// ---------- What this service produces ----------

// One human-readable notification. customerId is filled in from the order's
// orders.created event, since most other events only carry the orderId.
public type Notification record {|
    string notificationId;
    string topic;
    string orderId;
    string? customerId;
    string title;
    string message;
    string timestamp;
|};
