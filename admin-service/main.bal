import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;
import ballerinax/kafka;
import ballerinax/mongodb;

configurable int servicePort = 8087;
configurable string kafkaBootstrapServers = "localhost:29092";
configurable string mongoHost = "localhost";
configurable int mongoPort = 27017;


final mongodb:Client mongoClient = check new ({connection: mongoConnection()});
final mongodb:Collection ordersCollection;
final mongodb:Collection reportsCollection;

function mongoConnection() returns mongodb:ConnectionParameters {
    return {serverAddress: {host: mongoHost, port: mongoPort}};
}

function init() returns error? {
    mongodb:Database db = check mongoClient->getDatabase("admin_service");
    ordersCollection = check db->getCollection("orders");
    reportsCollection = check db->getCollection("reports");
    check ordersCollection->createIndex({orderId: 1}, {unique: true, name: "uniq_order_id"});
    check reportsCollection->createIndex({reportId: 1}, {unique: true, name: "uniq_report_id"});
}

function loadOrders() returns OrderRecord[]|error {
    stream<OrderRecord, error?> result = check ordersCollection->find({});
    OrderRecord[] orders = check from OrderRecord o in result select o;
    check result.close();
    return orders;
}

function loadReports() returns Report[]|error {
    stream<Report, error?> result = check reportsCollection->find({});
    Report[] reports = check from Report r in result select r;
    check result.close();
    return reports;
}

function findReport(string reportId) returns Report?|error {
    return check reportsCollection->findOne({reportId: reportId});
}

type OrderCreated record {
    string orderId;
    string restaurantId;
    decimal totalAmount;
    string timestamp;
};

type OrderStatusUpdated record {
    string orderId;
    string newStatus;
    string timestamp;
};

type DeliveryCompleted record {
    string orderId;
    string timestamp;
};

listener kafka:Listener eventListener = new (kafkaBootstrapServers, {
    groupId: "admin-service",
    topics: ["orders.created", "orders.status_updated", "delivery.completed"],
    offsetReset: kafka:OFFSET_RESET_EARLIEST,
    autoCommit: false
});

service on eventListener {
    remote function onConsumerRecord(kafka:Caller caller, kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord kafkaRecord in records {
            error? result = saveEvent(kafkaRecord);
            if result is error {
                log:printError("Could not process event", result);
            }
        }
        check caller->commit();
    }
}

function saveEvent(kafka:BytesConsumerRecord kafkaRecord) returns error? {
    string topic = kafkaRecord.offset.partition.topic;
    string payload = check string:fromBytes(kafkaRecord.value);
    string orderId;
    map<json> fields;

    if topic == "orders.created" {
        OrderCreated event = check payload.fromJsonStringWithType(OrderCreated);
        orderId = event.orderId;
        fields = {restaurantId: event.restaurantId, totalAmount: event.totalAmount, createdAt: event.timestamp};
    } else if topic == "orders.status_updated" {
        OrderStatusUpdated event = check payload.fromJsonStringWithType(OrderStatusUpdated);
        orderId = event.orderId;
        if event.newStatus == "DELIVERED" {
            fields = {deliveredAt: event.timestamp};
        } else if event.newStatus == "CANCELLED" {
            fields = {cancelledAt: event.timestamp};
        } else {
            return; 
        }
    } else {
        DeliveryCompleted event = check payload.fromJsonStringWithType(DeliveryCompleted);
        orderId = event.orderId;
        fields = {deliveredAt: event.timestamp};
    }

    fields["orderId"] = orderId;
    _ = check ordersCollection->updateOne({orderId: orderId}, {set: fields}, {upsert: true});
    log:printInfo("Recorded event", topic = topic, orderId = orderId);
}

service /admin on new http:Listener(servicePort) {

    resource function post reports() returns Report|http:InternalServerError {
        OrderRecord[]|error orders = loadOrders();
        if orders is error {
            log:printError("Could not load orders", orders);
            return <http:InternalServerError>{body: {message: "Could not load order data"}};
        }

        Report report = buildReport(uuid:createType1AsString(), time:utcToString(time:utcNow()), orders);

        error? saveResult = reportsCollection->insertOne(report);
        if saveResult is error {
            log:printError("Could not save report", saveResult);
            return <http:InternalServerError>{body: {message: "Could not save report"}};
        }
        return report;
    }

    resource function get reports() returns Report[]|http:InternalServerError {
        Report[]|error reports = loadReports();
        if reports is error {
            log:printError("Could not load reports", reports);
            return <http:InternalServerError>{body: {message: "Could not load reports"}};
        }
        return reports;
    }

    resource function get reports/[string reportId]() returns Report|http:NotFound|http:InternalServerError {
        Report?|error report = findReport(reportId);
        if report is error {
            log:printError("Could not load report", report);
            return <http:InternalServerError>{body: {message: "Could not load report"}};
        }
        if report is () {
            return <http:NotFound>{body: {message: "Report not found: " + reportId}};
        }
        return report;
    }
}
