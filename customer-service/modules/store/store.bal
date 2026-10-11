import ballerina/log;
import ballerinax/mongodb;
import dsa612s/customer_service.customer;

// ---------- MongoDB configuration ----------
configurable string mongoHost = "mongo";
configurable int mongoPort = 27017;
configurable string mongoDatabase = "customer_service";
configurable string mongoUsername = "";
configurable string mongoPassword = "";
configurable string mongoAuthDatabase = "admin";

isolated function buildConnectionParams() returns mongodb:ConnectionParameters {
    mongodb:ConnectionParameters params = {
        serverAddress: {host: mongoHost, port: mongoPort}
    };
    if mongoUsername != "" && mongoPassword != "" {
        params.auth = <mongodb:ScramSha256AuthCredential>{
            username: mongoUsername,
            password: mongoPassword,
            database: mongoAuthDatabase
        };
    }
    return params;
}

final mongodb:Client mongoClient = check new ({connection: buildConnectionParams()});
final mongodb:Database customerDatabase;

// Two collections, deliberately:
//
//   customers      one document per customer, with their saved addresses
//                  embedded (an address is only ever read as part of a profile,
//                  so there is no reason to make it a separate document).
//   order_history  one document per order. NOT embedded in the customer, because
//                  it grows without bound as the customer keeps ordering, and it
//                  is written by the Kafka consumer independently of profile
//                  edits - embedding it would make every status event rewrite
//                  the whole customer document.
final mongodb:Collection customerCollection;
final mongodb:Collection orderHistoryCollection;

function init() returns error? {
    customerDatabase = check mongoClient->getDatabase(mongoDatabase);
    customerCollection = check customerDatabase->getCollection("customers");
    orderHistoryCollection = check customerDatabase->getCollection("order_history");

    // customerId is the key the whole platform uses (it is what arrives on
    // orders.created), so it must be unique even though Mongo's own _id is also
    // generated per document.
    check customerCollection->createIndex({customerId: 1}, {unique: true, name: "uniq_customer_id"});

    // Email is the human-facing identity. The registration endpoint checks for a
    // duplicate first, but two simultaneous registrations would both pass that
    // check - this index is what actually stops the second one.
    check customerCollection->createIndex({email: 1}, {unique: true, name: "uniq_customer_email"});

    // History is keyed on orderId (one document per order, upserted so replayed
    // Kafka events don't duplicate it) and read by customerId.
    check orderHistoryCollection->createIndex({orderId: 1}, {unique: true, name: "uniq_order_id"});
    check orderHistoryCollection->createIndex({customerId: 1}, {name: "idx_customer_id"});

    log:printInfo("Connected to MongoDB", database = mongoDatabase, host = mongoHost, port = mongoPort);
}

// ---------- Customers ----------

public isolated function saveCustomer(customer:Customer newCustomer) returns error? {
    check customerCollection->insertOne(newCustomer);
}

public isolated function findCustomerById(string customerId) returns customer:Customer?|error {
    return check customerCollection->findOne({customerId: customerId});
}

// Callers must pass an email already put through customer:normaliseEmail - that
// is the form stored in the unique index.
public isolated function findCustomerByEmail(string email) returns customer:Customer?|error {
    return check customerCollection->findOne({email: email});
}

public isolated function findAllCustomers() returns customer:Customer[]|error {
    stream<customer:Customer, error?> resultStream = check customerCollection->find({});
    customer:Customer[] customers = check from customer:Customer c in resultStream
        select c;
    check resultStream.close();
    return customers;
}

// Email is deliberately not updatable here: it is the unique identity, and
// changing it would need the same duplicate handling as registration.
public isolated function updateCustomerProfile(string customerId, string fullName, string phone,
        string updatedAt) returns error? {
    mongodb:UpdateResult result = check customerCollection->updateOne(
        {customerId: customerId},
        {set: {fullName: fullName, phone: phone, updatedAt: updatedAt}}
    );
    if result.matchedCount == 0 {
        return error(string `Customer ${customerId} not found`);
    }
}

// Addresses are rewritten as a whole array rather than patched element by
// element: customer:addAddress / updateAddress / removeAddress have already
// produced the correct list, including the single-default invariant.
public isolated function replaceAddresses(string customerId, customer:Address[] addresses,
        string updatedAt) returns error? {
    mongodb:UpdateResult result = check customerCollection->updateOne(
        {customerId: customerId},
        {set: {addresses: addresses.toJson(), updatedAt: updatedAt}}
    );
    if result.matchedCount == 0 {
        return error(string `Customer ${customerId} not found`);
    }
}

// Returns false when there was no such customer, so the caller can answer 404.
public isolated function deleteCustomer(string customerId) returns boolean|error {
    mongodb:DeleteResult result = check customerCollection->deleteOne({customerId: customerId});
    return result.deletedCount > 0;
}

// ---------- Order history (written by the Kafka consumer only) ----------

// Upsert rather than insert: Kafka guarantees at-least-once delivery, so the
// same orders.created event can arrive twice (or the topic can be replayed from
// the beginning when the consumer group is reset). Keying on orderId makes
// re-processing a no-op instead of a duplicate history row.
public isolated function upsertOrderHistory(customer:OrderHistoryEntry entry) returns error? {
    _ = check orderHistoryCollection->updateOne(
        {orderId: entry.orderId},
        {
            set: {
                orderId: entry.orderId,
                customerId: entry.customerId,
                restaurantId: entry.restaurantId,
                items: entry.items.toJson(),
                totalAmount: entry.totalAmount,
                status: entry.status,
                placedAt: entry.placedAt,
                updatedAt: entry.updatedAt
            }
        },
        {upsert: true}
    );
}

// Returns false when no history row exists for that order yet -
// orders.status_updated carries no customerId, so there is nothing to create
// the row from and the caller just logs and moves on.
public isolated function updateOrderHistoryStatus(string orderId, string newStatus,
        string updatedAt) returns boolean|error {
    mongodb:UpdateResult result = check orderHistoryCollection->updateOne(
        {orderId: orderId},
        {set: {status: newStatus, updatedAt: updatedAt}}
    );
    return result.matchedCount > 0;
}

public isolated function findOrderHistoryByCustomer(string customerId)
        returns customer:OrderHistoryEntry[]|error {
    stream<customer:OrderHistoryEntry, error?> resultStream =
        check orderHistoryCollection->find({customerId: customerId});
    customer:OrderHistoryEntry[] history = check from customer:OrderHistoryEntry entry in resultStream
        select entry;
    check resultStream.close();
    return history;
}

public isolated function deleteOrderHistoryForCustomer(string customerId) returns error? {
    _ = check orderHistoryCollection->deleteMany({customerId: customerId});
}
