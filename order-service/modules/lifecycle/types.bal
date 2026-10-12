// Pure order domain model and lifecycle rules - no HTTP, Kafka, or DB
// dependencies here on purpose, so this module can be unit tested (and
// reasoned about) in complete isolation from the rest of the service.

public enum OrderStatus {
    CREATED,
    CONFIRMED,
    PREPARING,
    READY,
    OUT_FOR_DELIVERY,
    DELIVERED,
    CANCELLED
}

public type OrderItem record {|
    string itemId;
    string name;
    int quantity;
    decimal unitPrice;
|};

public type Order record {|
    string orderId;
    string customerId;
    string restaurantId;
    OrderItem[] items;
    decimal totalAmount;
    OrderStatus status;
    // Last payments.completed outcome for this order ("SUCCESS" / "FAILED").
    // Absent until the Payment Service has reported - optional so orders saved
    // before this field existed still deserialise.
    string paymentStatus?;
    // Why the order was cancelled automatically (e.g. the restaurant rejected it).
    string cancellationReason?;
    string createdAt;
    string updatedAt;
|};

public type CreateOrderRequest record {|
    string customerId;
    string restaurantId;
    OrderItem[] items;
|};

public type UpdateStatusRequest record {|
    OrderStatus status;
|};

// ---------- Valid state transitions ----------
//
//   CREATED -> CONFIRMED -> PREPARING -> READY -> OUT_FOR_DELIVERY -> DELIVERED
//      \-> CANCELLED        \-> CANCELLED  \-> CANCELLED
//
// READY and later cannot be cancelled: the food is already made/in transit.
public isolated function isValidTransition(OrderStatus current, OrderStatus next) returns boolean {
    match current {
        CREATED => {
            return next == CONFIRMED || next == CANCELLED;
        }
        CONFIRMED => {
            return next == PREPARING || next == CANCELLED;
        }
        PREPARING => {
            return next == READY || next == CANCELLED;
        }
        READY => {
            return next == OUT_FOR_DELIVERY;
        }
        OUT_FOR_DELIVERY => {
            return next == DELIVERED;
        }
        _ => {
            return false; // DELIVERED and CANCELLED are terminal states
        }
    }
}

public isolated function computeOrderTotal(OrderItem[] items) returns decimal {
    decimal total = 0;
    foreach OrderItem item in items {
        total += item.unitPrice * <decimal>item.quantity;
    }
    return total;
}

public const int MAX_ITEM_QUANTITY = 50;

// Returns a message describing the first problem, or () when the request is valid.
public isolated function validateCreateOrder(CreateOrderRequest req) returns string? {
    if req.customerId.trim() == "" {
        return "customerId is required";
    }
    if req.restaurantId.trim() == "" {
        return "restaurantId is required";
    }
    if req.items.length() == 0 {
        return "Order must contain at least one item";
    }
    foreach OrderItem item in req.items {
        if item.itemId.trim() == "" || item.name.trim() == "" {
            return "Every item needs an itemId and a name";
        }
        if item.quantity < 1 || item.quantity > MAX_ITEM_QUANTITY {
            return string `Quantity of ${item.name} must be between 1 and ${MAX_ITEM_QUANTITY}`;
        }
        if item.unitPrice <= 0d {
            return string `Price of ${item.name} must be greater than zero`;
        }
    }
    return ();
}
