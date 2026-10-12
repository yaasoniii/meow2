import ballerina/log;
import ballerinax/mongodb;
import dsa612s/delivery_service.domain;


// --------------- MongoDB config -----------
configurable string mongoHost = "mongo";
configurable int mongoPort = 27017;
configurable string mongoDatabase = "delivery_service";
configurable string mongoUsername = "";
configurable string mongoPassword = "";
configurable string mongoAuthDatabase = "admin";

isolated function buildConnectionParams() returns mongodb:ConnectionParameters {
    mongodb:ConnectionParameters params ={
        serverAddress: {host: mongoHost, port: mongoPort}
    };
    if mongoUsername != "" && mongoPassword != "" {
        params.auth = <mongodb:ScramSha256AuthCredential>{
            username: mongoUsername,
            password:mongoPassword,
            database:mongoAuthDatabase
        };
    }
    return params;
}

final mongodb:Client mongoClient = check new ({connection: buildConnectionParams()});
final mongodb:Database deliveryDatabase;
final mongodb:Collection driverCollection;
final mongodb:Collection deliveryCollection;


function init() returns error? {
    deliveryDatabase = check mongoClient->getDatabase(mongoDatabase);
    driverCollection = check deliveryDatabase->getCollection("drivers");
    deliveryCollection = check deliveryDatabase->getCollection("deliveries");

    check driverCollection->createIndex({driverId: 1}, {unique: true, name: "uniq_driver_id"});
    check deliveryCollection->createIndex({deliveryId: 1}, {unique: true, name: "uniq_delivery_id"});
    //One delivery per order
     // safe: the second insert fails instead of creating a duplicate delivery.
    check deliveryCollection->createIndex({orderId: 1}, {unique: true, name: "uniq_order_id"});
    // Dispatch looks for free drivers and waiting deliveries (oldest first);
    // the driver app lists a driver's own deliveries.
    check driverCollection->createIndex({status: 1}, {name: "idx_driver_status"});
    check deliveryCollection->createIndex({status: 1, createdAt: 1}, {name: "idx_status_created"});
    check deliveryCollection->createIndex({driverId: 1, createdAt: -1}, {name: "idx_driver_created"});

    log:printInfo("Connected to MongoDB", database = mongoDatabase, host = mongoHost, port = mongoPort);
}

// ---------- Drivers ----------

public isolated function saveDriver(domain:Driver driver) returns error? {
    check driverCollection->insertOne(driver);
}

public isolated function findDriverById(string driverId) returns domain:Driver?|error {
    return check driverCollection->findOne({driverId: driverId});
}

public isolated function findAllDrivers() returns domain:Driver[]|error {
    stream<domain:Driver, error?> resultStream = check driverCollection->find({});
    domain:Driver[] drivers = check from domain:Driver d in resultStream
        select d;
    check resultStream.close();
    return drivers;
}

public isolated function fetchAvailableDrivers() returns domain:Driver[]|error {
    stream<domain:Driver, error?> resultStream = check driverCollection->find({status: domain:AVAILABLE});
    domain:Driver[] drivers = check from domain:Driver d in resultStream
        select d;
    check resultStream.close();
    return drivers;
}

// Claims a driver for a delivery in a single atomic update. The filter includes
// status: AVAILABLE, so if two deliveries race for the same driver only one
// update matches - the loser gets false and moves on to another driver.
public isolated function claimDriver(string driverId, string deliveryId) returns boolean|error {
    mongodb:UpdateResult result = check driverCollection->updateOne(
        {driverId: driverId, status: domain:AVAILABLE},
        {set: {status: domain:ON_DELIVERY, currentDeliveryId: deliveryId}}
    );
    return result.matchedCount > 0;
}

public isolated function updateDriverStatus(string driverId, domain:DriverStatus status,
        string? currentDeliveryId) returns error? {
    mongodb:UpdateResult result = check driverCollection->updateOne(
        {driverId: driverId},
        {set: {status: status, currentDeliveryId: currentDeliveryId}}
    );
    if result.matchedCount == 0 {
        return error(string `Driver ${driverId} not found`);
    }
}

// ---------- Deliveries ----------

public isolated function saveDelivery(domain:Delivery delivery) returns error? {
    check deliveryCollection->insertOne(delivery);
}

public isolated function findDeliveryById(string deliveryId) returns domain:Delivery?|error {
    return check deliveryCollection->findOne({deliveryId: deliveryId});
}

public isolated function findDeliveryByOrderId(string orderId) returns domain:Delivery?|error {
    return check deliveryCollection->findOne({orderId: orderId});
}

// Newest first. `filter` is a plain Mongo filter, e.g. {driverId: "..."}.
public isolated function findDeliveries(map<json> filter) returns domain:Delivery[]|error {
    stream<domain:Delivery, error?> resultStream = check deliveryCollection->find(filter, {sort: {createdAt: -1}});
    domain:Delivery[] deliveries = check from domain:Delivery d in resultStream
        select d;
    check resultStream.close();
    return deliveries;
}

// Oldest first, so waiting deliveries get drivers in the order they were paid for.
public isolated function findPendingDeliveries() returns domain:Delivery[]|error {
    stream<domain:Delivery, error?> resultStream =
        check deliveryCollection->find({status: domain:PENDING}, {sort: {createdAt: 1}});
    domain:Delivery[] deliveries = check from domain:Delivery d in resultStream
        select d;
    check resultStream.close();
    return deliveries;
}

public isolated function applyDeliveryStatusTransition(string deliveryId, domain:DeliveryStatus previousStatus,
        domain:DeliveryStatus newStatus, string updatedAt, string? driverId = ()) returns error? {
    map<json> setFields = {status: newStatus, updatedAt: updatedAt};
    if driverId is string {
        setFields["driverId"] = driverId;
    }
    mongodb:UpdateResult result = check deliveryCollection->updateOne(
        {deliveryId: deliveryId, status: previousStatus},
        {set: setFields}
    );
    if result.matchedCount == 0 {
        return error(string `Delivery ${deliveryId} not found, or its status changed concurrently ` +
                string `(expected ${previousStatus})`);
    }
}