//pure delivery domain model

public enum DriverStatus {
    AVAILABLE,
    ON_DELIVERY,
    UNAVAILABLE
}

public enum DeliveryStatus {
    PENDING,
    ASSIGNED,
    PICKED_UP,
    IN_PROGRESS,
    DELIVERED,
    CANCELLED
}

public type Driver record {|
    string driverId;
    string name;
    string phoneNumber;
    DriverStatus status;
    string plateNumber;
    string vehicleType;
    string? currentDeliveryId =();
|};

public type Delivery record {|
    string deliveryId;
    string orderId;
    string? driverId =();
    DeliveryStatus status;
    string createdAt;
    string? updatedAt = ();
|};

public type RegisterDriverRequest record {|
    string name;
    string phoneNumber;
    string plateNumber;
    string vehicleType;
|};

public type UpdateDriverStatusRequest record {|
    DriverStatus status;
|};

public type UpdateDeliveryStatusRequest record {|
    DeliveryStatus status;
|};

