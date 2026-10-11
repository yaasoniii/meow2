import ballerina/http;
import ballerina/log;
import ballerina/random;
import ballerina/sql;
import ballerina/time;
import ballerina/uuid;
import ballerinax/kafka;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;

configurable int servicePort = 8084;
configurable decimal successRatePercent = 85;

public enum PaymentStatus {
    PENDING,
    SUCCESS,
    FAILED
}

public type Payment record {|
    string paymentId;
    string orderId;
    string customerId;
    decimal amount;
    PaymentStatus status;
    string createdAt;
    string updatedAt;
|};

public type PaymentRequest record {|
    string orderId;
    string customerId;
    decimal amount;
|};

// orders.created as published by the Order Service. Open record: the event also
// carries restaurantId, items and timestamp, which payment doesn't need.
public type OrderCreatedEvent record {
    string orderId;
    string customerId;
    decimal totalAmount;
};

// payments.completed - the shared contract (see the root README). status is
// "SUCCESS" or "FAILED".
public type PaymentCompletedEvent record {|
    string orderId;
    string paymentId;
    string customerId;
    decimal amount;
    string status;
    string timestamp;
|};

// ---------- Postgres ----------

configurable string dbHost = "payment-db";
configurable int dbPort = 5432;
configurable string dbName = "payments";
configurable string dbUser = "payment_user";
configurable string dbPassword = "payment_pass";

final postgresql:Client paymentDb = check new (
    host = dbHost,
    port = dbPort,
    database = dbName,
    username = dbUser,
    password = dbPassword
);

// Raw row shape: status comes back as plain text and is narrowed to
// PaymentStatus in toPayment. Aliases are quoted because Postgres folds
// unquoted identifiers to lower case.
type PaymentRow record {|
    string paymentId;
    string orderId;
    string customerId;
    decimal amount;
    string status;
    string createdAt;
    string updatedAt;
|};

function toPayment(PaymentRow row) returns Payment|error {
    return {
        paymentId: row.paymentId,
        orderId: row.orderId,
        customerId: row.customerId,
        amount: row.amount,
        status: check row.status.ensureType(),
        createdAt: row.createdAt,
        updatedAt: row.updatedAt
    };
}

function savePayment(Payment payment) returns error? {
    _ = check paymentDb->execute(`
        INSERT INTO payments (payment_id, order_id, customer_id, amount, status, created_at, updated_at)
        VALUES (${payment.paymentId}::uuid, ${payment.orderId}::uuid, ${payment.customerId}::uuid,
                ${payment.amount}, ${payment.status}, ${payment.createdAt}::timestamptz, ${payment.updatedAt}::timestamptz)
    `);
}

function findPaymentById(string paymentId) returns Payment|error? {
    stream<PaymentRow, sql:Error?> result = paymentDb->query(`
        SELECT payment_id::text AS "paymentId", order_id::text AS "orderId", customer_id::text AS "customerId",
               amount, status,
               to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS "createdAt",
               to_char(updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS "updatedAt"
        FROM payments WHERE payment_id = ${paymentId}::uuid
    `);
    record {|PaymentRow value;|}? next = check result.next();
    check result.close();
    if next is () {
        return ();
    }
    return toPayment(next.value);
}

function findPaymentsByOrderId(string orderId) returns Payment[]|error {
    stream<PaymentRow, sql:Error?> result = paymentDb->query(`
        SELECT payment_id::text AS "paymentId", order_id::text AS "orderId", customer_id::text AS "customerId",
               amount, status,
               to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS "createdAt",
               to_char(updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS "updatedAt"
        FROM payments WHERE order_id = ${orderId}::uuid ORDER BY created_at
    `);
    PaymentRow[] rows = check from PaymentRow r in result select r;
    check result.close();
    return from PaymentRow r in rows select check toPayment(r);
}

function hasSuccessfulPayment(string orderId) returns boolean|error {
    Payment[] existing = check findPaymentsByOrderId(orderId);
    return existing.some(p => p.status == SUCCESS);
}

// ---------- Kafka ----------

configurable string kafkaBootstrapServers = "kafka:9092";
const string ORDERS_TOPIC = "orders.created";
const string PAYMENTS_TOPIC = "payments.completed";

final kafka:Producer paymentsProducer = check new (kafkaBootstrapServers, {
    clientId: "payment-service-producer",
    acks: "all",
    retryCount: 3
});

// autoCommit off, matching the other services: offsets are committed only after
// a batch has been handled, so a crash replays it instead of losing it.
listener kafka:Listener orderListener = new (kafkaBootstrapServers, {
    groupId: "payment-service-group",
    topics: [ORDERS_TOPIC],
    offsetReset: kafka:OFFSET_RESET_EARLIEST,
    autoCommit: false
});

// Simulated gateway: succeeds successRatePercent% of the time.
function simulateCharge() returns PaymentStatus|error {
    int roll = check random:createIntInRange(0, 100);
    return <decimal>roll < successRatePercent ? SUCCESS : FAILED;
}

function processPayment(string orderId, string customerId, decimal amount) returns Payment|error {
    string now = time:utcToString(time:utcNow());
    Payment payment = {
        paymentId: uuid:createType4AsString(),
        orderId,
        customerId,
        amount,
        status: check simulateCharge(),
        createdAt: now,
        updatedAt: now
    };
    check savePayment(payment);
    return payment;
}

function publishPaymentCompleted(Payment payment) returns error? {
    PaymentCompletedEvent event = {
        orderId: payment.orderId,
        paymentId: payment.paymentId,
        customerId: payment.customerId,
        amount: payment.amount,
        status: payment.status,
        timestamp: payment.updatedAt
    };
    check paymentsProducer->send({
        topic: PAYMENTS_TOPIC,
        key: payment.orderId.toBytes(),
        value: event.toJsonString().toBytes()
    });
    log:printInfo("Published payments.completed", orderId = payment.orderId, status = payment.status);
}

service on orderListener {
    remote function onConsumerRecord(kafka:Caller caller, kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord rec in records {
            error? result = handleOrderCreated(rec);
            if result is error {
                log:printError("Failed to process orders.created record", result);
            }
        }
        kafka:Error? commitResult = caller->commit();
        if commitResult is kafka:Error {
            log:printError("Failed to commit orders.created offsets", commitResult);
        }
    }
}

function handleOrderCreated(kafka:BytesConsumerRecord rec) returns error? {
    string msg = check string:fromBytes(rec.value);
    OrderCreatedEvent orderEvent = check msg.fromJsonStringWithType();
    log:printInfo("Received orders.created", orderId = orderEvent.orderId);

    // Kafka is at-least-once: a redelivered orders.created must not charge twice.
    if check hasSuccessfulPayment(orderEvent.orderId) {
        log:printInfo("Order already paid, skipping", orderId = orderEvent.orderId);
        return;
    }

    Payment payment = check processPayment(orderEvent.orderId, orderEvent.customerId, orderEvent.totalAmount);
    check publishPaymentCompleted(payment);
}

// ---------- REST API ----------

service /payments on new http:Listener(servicePort) {

    // Manual payment - used to retry an order whose automatic charge FAILED.
    // Refused (409) once the order already has a successful payment.
    resource function post initiate(PaymentRequest req)
            returns Payment|http:BadRequest|http:Conflict|http:InternalServerError {
        if !uuid:validate(req.orderId) || !uuid:validate(req.customerId) {
            return <http:BadRequest>{body: {message: "orderId and customerId must be UUIDs"}};
        }
        if req.amount <= 0d {
            return <http:BadRequest>{body: {message: "amount must be greater than zero"}};
        }

        boolean|error alreadyPaid = hasSuccessfulPayment(req.orderId);
        if alreadyPaid is error {
            log:printError("DB lookup failed", alreadyPaid);
            return <http:InternalServerError>{body: {message: "failed to process payment"}};
        }
        if alreadyPaid {
            return <http:Conflict>{body: {message: "order " + req.orderId + " is already paid"}};
        }

        Payment|error payment = processPayment(req.orderId, req.customerId, req.amount);
        if payment is error {
            log:printError("Failed to process/persist payment", payment);
            return <http:InternalServerError>{body: {message: "failed to process payment"}};
        }
        error? publishResult = publishPaymentCompleted(payment);
        if publishResult is error {
            log:printError("Failed to publish payments.completed", publishResult);
            return <http:InternalServerError>{body: {message: "payment processed but event publish failed"}};
        }
        return payment;
    }

    resource function get health() returns json {
        return {status: "UP", 'service: "payment-service"};
    }

    resource function get byOrder/[string orderId]() returns Payment[]|http:InternalServerError {
        if !uuid:validate(orderId) {
            return []; // not a UUID, so no payment can reference it
        }
        Payment[]|error payments = findPaymentsByOrderId(orderId);
        if payments is error {
            log:printError("DB lookup failed", payments);
            return <http:InternalServerError>{body: {message: "lookup failed"}};
        }
        return payments;
    }

    resource function get [string paymentId]() returns Payment|http:NotFound|http:InternalServerError {
        if !uuid:validate(paymentId) {
            return <http:NotFound>{body: {message: "payment not found: " + paymentId}};
        }
        Payment|error? payment = findPaymentById(paymentId);
        if payment is error {
            log:printError("DB lookup failed", payment);
            return <http:InternalServerError>{body: {message: "lookup failed"}};
        }
        if payment is () {
            return <http:NotFound>{body: {message: "payment not found: " + paymentId}};
        }
        return payment;
    }
}
