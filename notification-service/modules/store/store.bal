import ballerina/log;
import ballerinax/mongodb;

// ---------- MongoDB configuration ----------
configurable string mongoHost = "mongo";
configurable int mongoPort = 27017;
configurable string mongoDatabase = "notification_service";
configurable string mongoUsername = "";
configurable string mongoPassword = "";
configurable string mongoAuthDatabase = "admin";

public enum Audience {
    CUSTOMER,
    RESTAURANT,
    DRIVER
}

// One alert for one party about one order.
public type Notification record {|
    // "<topic>-<partition>-<offset>-<audience>": unique per Kafka record and
    // recipient, so a redelivered event overwrites instead of duplicating.
    string notificationId;
    string topic;
    string orderId;
    Audience audience;
    string? recipientId; // customerId / restaurantId / driverId
    string[] channels; // e.g. ["EMAIL", "SMS"]
    string title;
    string message;
    string timestamp;
|};

// Who is involved in an order, pieced together from events: orders.created
// gives the customer and restaurant, delivery.assigned gives the driver. Most
// events only carry orderId, so this is how they reach the right people.
public type OrderContext record {|
    string orderId;
    string customerId?;
    string restaurantId?;
    string driverId?;
|};

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
final mongodb:Database notificationDatabase;
final mongodb:Collection notificationCollection;
final mongodb:Collection orderContextCollection;

function init() returns error? {
    notificationDatabase = check mongoClient->getDatabase(mongoDatabase);
    notificationCollection = check notificationDatabase->getCollection("notifications");
    orderContextCollection = check notificationDatabase->getCollection("order_contexts");

    check notificationCollection->createIndex({notificationId: 1}, {unique: true, name: "uniq_notification_id"});
    // Compound indexes matching the inbox queries, including their newest-first sort.
    check notificationCollection->createIndex({recipientId: 1, timestamp: -1}, {name: "idx_recipient_time"});
    check notificationCollection->createIndex({orderId: 1, timestamp: -1}, {name: "idx_order_time"});
    check orderContextCollection->createIndex({orderId: 1}, {unique: true, name: "uniq_order_id"});

    log:printInfo("Connected to MongoDB", database = mongoDatabase, host = mongoHost, port = mongoPort);
}

// Upsert keyed on notificationId: replaying a Kafka record is a no-op.
public isolated function saveNotification(Notification notification) returns error? {
    map<json> fields = check notification.toJson().ensureType();
    _ = check notificationCollection->updateOne(
        {notificationId: notification.notificationId}, {set: fields}, {upsert: true});
}

// Newest first, optionally filtered by recipient, audience and/or order.
public isolated function listNotifications(string? recipientId, string? audience, string? orderId, int 'limit)
        returns Notification[]|error {
    map<json> filter = {};
    if recipientId is string {
        filter["recipientId"] = recipientId;
    }
    if audience is string {
        filter["audience"] = audience;
    }
    if orderId is string {
        filter["orderId"] = orderId;
    }
    stream<Notification, error?> resultStream =
        check notificationCollection->find(filter, {sort: {timestamp: -1}, 'limit: 'limit});
    Notification[] notifications = check from Notification n in resultStream
        select n;
    check resultStream.close();
    return notifications;
}

// Merges the given fields (customerId / restaurantId / driverId) into the order's context.
public isolated function rememberOrder(string orderId, map<json> fields) returns error? {
    map<json> update = fields.clone();
    update["orderId"] = orderId;
    _ = check orderContextCollection->updateOne({orderId: orderId}, {set: update}, {upsert: true});
}

public isolated function findOrderContext(string orderId) returns OrderContext|error {
    OrderContext? found = check orderContextCollection->findOne({orderId: orderId});
    return found ?: {orderId};
}
