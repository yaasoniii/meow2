// Pure customer domain model - no HTTP, Kafka, or DB dependencies here on
// purpose, so this module can be unit tested (and reasoned about) in complete
// isolation from the rest of the service.

public type Address record {|
    string addressId;
    string label; // "Home", "Work", ...
    string street;
    string city;
    string postalCode;
    string country;
    boolean isDefault;
|};

public type Customer record {|
    string customerId;
    string fullName;
    string email; // normalised (trimmed + lowercased) - see normaliseEmail
    string phone;
    Address[] addresses;
    string createdAt;
    string updatedAt;
|};

public type OrderItem record {|
    string itemId;
    string name;
    int quantity;
    decimal unitPrice;
|};

// One customer-side snapshot of an order. Built entirely from the Order
// Service's orders.created / orders.status_updated events - the REST API never
// writes to it, it only reads it back as "order history".
public type OrderHistoryEntry record {|
    string orderId;
    string customerId;
    string restaurantId;
    OrderItem[] items;
    decimal totalAmount;
    string status;
    string placedAt;
    string updatedAt;
|};

// ---------- Request payloads ----------

public type RegisterCustomerRequest record {|
    string fullName;
    string email;
    string phone;
|};

// Email is the customer's identity (unique index in Mongo), so it deliberately
// isn't editable through the profile-update endpoint.
public type UpdateCustomerRequest record {|
    string fullName;
    string phone;
|};

public type AddressRequest record {|
    string label;
    string street;
    string city;
    string postalCode;
    string country;
    boolean isDefault = false;
|};

// Returned by the validate* functions below instead of an error, so the REST
// layer can map it straight onto a 400 body that names the offending field.
public type ValidationError record {|
    string fieldName;
    string message;
|};
