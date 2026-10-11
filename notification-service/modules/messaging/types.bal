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

// Event received when payment processing is completed.
public type PaymentCompletedEvent record {
    string orderId;
    string paymentId;
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