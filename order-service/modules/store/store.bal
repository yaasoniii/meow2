import ballerina/log;
import ballerinax/mongodb;
import dsa612s/order_service.lifecycle;

// ---------- MongoDB configuration ----------
configurable string mongoHost = "mongo";
configurable int mongoPort = 27017;
configurable string mongoDatabase = "order_service";
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
final mongodb:Database orderDatabase;
final mongodb:Collection orderCollection;

function init() returns error? {
    orderDatabase = check mongoClient->getDatabase(mongoDatabase);
    orderCollection = check orderDatabase->getCollection("orders");

    // orderId is the natural key the whole platform uses to reference an order,
    // so it must be unique even though Mongo's own _id is also generated per document.
    check orderCollection->createIndex({orderId: 1}, {unique: true, name: "uniq_order_id"});
    log:printInfo("Connected to MongoDB", database = mongoDatabase, host = mongoHost, port = mongoPort);
}

public isolated function saveOrder(lifecycle:Order newOrder) returns error? {
    check orderCollection->insertOne(newOrder);
}

public isolated function findOrderById(string orderId) returns lifecycle:Order?|error {
    return check orderCollection->findOne({orderId: orderId});
}

// Newest first. `filter` is a plain Mongo filter, e.g. {customerId: "..."}.
public isolated function findOrders(map<json> filter) returns lifecycle:Order[]|error {
    stream<lifecycle:Order, error?> resultStream = check orderCollection->find(filter, {sort: {createdAt: -1}});
    lifecycle:Order[] orders = check from lifecycle:Order o in resultStream
        select o;
    check resultStream.close();
    return orders;
}

// Records the latest payment outcome without touching the lifecycle status -
// whether the order can advance is decided by the caller.
public isolated function setPaymentStatus(string orderId, string paymentStatus, string updatedAt) returns error? {
    mongodb:UpdateResult result = check orderCollection->updateOne(
        {orderId: orderId},
        {set: {paymentStatus: paymentStatus, updatedAt: updatedAt}}
    );
    if result.matchedCount == 0 {
        return error(string `Order ${orderId} not found`);
    }
}

// Applies a status transition atomically: the filter includes the expected
// previous status, so a concurrent update that already moved the order on
// loses this write instead of silently clobbering it (optimistic concurrency).
public isolated function applyStatusTransition(string orderId, lifecycle:OrderStatus previousStatus,
        lifecycle:OrderStatus newStatus, string updatedAt) returns error? {
    mongodb:UpdateResult result = check orderCollection->updateOne(
        {orderId: orderId, status: previousStatus},
        {set: {status: newStatus, updatedAt: updatedAt}}
    );
    if result.matchedCount == 0 {
        return error(string `Order ${orderId} not found, or its status changed concurrently ` +
                string `(expected ${previousStatus})`);
    }
}
