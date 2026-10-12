// Mirrors the shape Order Service publishes on "orders.created".
// Open record — so any fields the Order Service adds later don't
// break deserialization on our side.
public type OrderItemPayload record {
    string itemId;
    string name;
    int quantity;
    decimal unitPrice;
};

public type OrderCreatedEvent record {
    string orderId;
    string customerId;
    string restaurantId;
    OrderItemPayload[] items;
    decimal totalAmount;
    string timestamp;
};

// What we publish on "restaurant.status". Our own contract, so it's
// closed — but the shape/status values are provisional until whoever
// consumes this (Notification Service, maybe Order Service) confirms.
public type RestaurantStatusEvent record {|
    string restaurantId;
    string orderId;
    string status; // "ACKNOWLEDGED" or "REJECTED"
    string? reason; // set when REJECTED
    string timestamp;
|};