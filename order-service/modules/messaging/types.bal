import dsa612s/order_service.lifecycle;

// ---------- Event payloads published to Kafka ----------
type OrderCreatedEvent record {|
    string orderId;
    string customerId;
    string restaurantId;
    lifecycle:OrderItem[] items;
    decimal totalAmount;
    string timestamp;
|};

type OrderStatusUpdatedEvent record {|
    string orderId;
    lifecycle:OrderStatus previousStatus;
    lifecycle:OrderStatus newStatus;
    string timestamp;
|};

// ---------- Event payloads consumed from other services ----------
// All open records (`record { }`), so extra fields the owning service adds
// later flow through instead of failing to deserialise.

// payments.completed - owned by the Payment Service. Agreed status values are
// "SUCCESS" and "FAILED" (see the Kafka contract in the root README).
type PaymentCompletedEvent record {
    string orderId;
    string status;
    string paymentId?;
    string customerId?;
    decimal amount?;
    string timestamp?;
};

// restaurant.status - owned by the Restaurant Service. "ACKNOWLEDGED" confirms
// the order; "REJECTED" (with a reason) cancels it.
type RestaurantStatusEvent record {
    string orderId;
    string status;
    string restaurantId?;
    string? reason?;
    string timestamp?;
};

// delivery.status_updated - owned by the Delivery Service, published on every
// delivery transition. PICKED_UP and DELIVERED drive the order's last two steps.
type DeliveryStatusUpdatedEvent record {
    string orderId;
    string newStatus;
    string deliveryId?;
    string previousStatus?;
    string timestamp?;
};
