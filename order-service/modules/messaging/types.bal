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
// NOTE: payments.completed is owned by the Payment Service. Field names below
// are an assumption - confirm the exact schema with whoever implements that
// service and adjust this type (and consumer.bal) if it differs. It's
// declared as an open record so extra fields they add don't break us.
type PaymentCompletedEvent record {
    string orderId;
    string status;
    decimal amount?;
    string currency?;
    string timestamp?;
};
