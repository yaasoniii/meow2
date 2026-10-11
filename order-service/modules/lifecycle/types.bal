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
