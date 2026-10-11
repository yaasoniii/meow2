import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;
import ballerina/sql;
import ballerinax/kafka;
import ballerinax/postgresql;


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

public type OrderCreatedEvent record {|
    string orderId;
    string customerId;
    decimal amount;
|};

public type PaymentCompletedEvent record {|
    string orderId;
    string paymentId;
    string status;
    string timestamp;
|};


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

function savePayment(Payment payment) returns error? {
    _ = check paymentDb->execute(`
        INSERT INTO payments (payment_id, order_id, customer_id, amount, status, created_at, updated_at)
        VALUES (${payment.paymentId}::uuid, ${payment.orderId}::uuid, ${payment.customerId}::uuid,
                ${payment.amount}, ${payment.status}, ${payment.createdAt}::timestamptz, ${payment.updatedAt}::timestamptz)
    `);
}

function findPaymentById(string paymentId) returns Payment|error? {
    stream<Payment, sql:Error?> result = paymentDb->query(`
        SELECT payment_id AS paymentId, order_id AS orderId, customer_id AS customerId,
               amount, status, created_at AS createdAt, updated_at AS updatedAt
        FROM payments WHERE payment_id = ${paymentId}::uuid
    `);
    record {| Payment value; |}|error? next = result.next();
    check result.close();

    if next is error {
        return next;
    }
    if next is () {
        return ();
    }
    return next.value;
}

function findPaymentsByOrderId(string orderId) returns Payment[]|error {
    stream<Payment, sql:Error?> result = paymentDb->query(`
        SELECT payment_id AS paymentId, order_id AS orderId, customer_id AS customerId,
               amount, status, created_at AS createdAt, updated_at AS updatedAt
        FROM payments WHERE order_id = ${orderId}::uuid ORDER BY created_at
    `);
    Payment[] payments = check from Payment p in result select p;
    check result.close();
    return payments;
}

configurable string kafkaBootstrap = "kafka:9092";
const string ORDERS_TOPIC = "orders.created";
const string PAYMENTS_TOPIC = "payments.completed";

kafka:ProducerConfiguration producerConfig = {
    clientId: "payment-service-producer",
    acks: "all",
    retryCount: 3
};

final kafka:Producer paymentsProducer = check new (kafkaBootstrap, producerConfig);

kafka:ConsumerConfiguration consumerConfig = {
    groupId: "payment-service-group",
    topics: [ORDERS_TOPIC],
    offsetReset: kafka:OFFSET_RESET_EARLIEST,
    autoCommit: true
};

listener kafka:Listener orderListener = new (kafkaBootstrap, consumerConfig);



function processPayment(string orderId, string customerId, decimal amount) returns Payment|error {
    string paymentId = uuid:createType1AsString();
    string now = time:utcToString(time:utcNow());

    int lastByte = paymentId.length() > 0 ? <int>paymentId[paymentId.length() - 1].toBytes()[0] : 0;
    PaymentStatus status = (lastByte % 100) < 85 ? SUCCESS : FAILED;

    Payment payment = {
        paymentId,
        orderId,
        customerId,
        amount,
        status,
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
        status: payment.status,
        timestamp: payment.updatedAt
    };
    check paymentsProducer->send({
        topic: PAYMENTS_TOPIC,
        value: event.toJsonString().toBytes()
    });
    log:printInfo(string `Published payments.completed orderId=${payment.orderId} status=${payment.status}`);
}


service on orderListener {
    remote function onConsumerRecord(kafka:Caller caller, kafka:BytesConsumerRecord[] records) returns error? {
        foreach var rec in records {
            string msg = check string:fromBytes(rec.value);
            OrderCreatedEvent orderEvent = check msg.fromJsonStringWithType();
            log:printInfo(string `Received orders.created orderId=${orderEvent.orderId}`);

            Payment|error payment = processPayment(orderEvent.orderId, orderEvent.customerId, orderEvent.amount);
            if payment is error {
                log:printError("Failed to process/persist payment", payment);
                continue;
            }
            error? publishResult = publishPaymentCompleted(payment);
            if publishResult is error {
                log:printError("Failed to publish payments.completed", publishResult);
            }
        }
    }
}


service /payments on new http:Listener(8083) {


    resource function post initiate(PaymentRequest req) returns Payment|http:InternalServerError {
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

    resource function get [string paymentId]() returns Payment|http:NotFound|http:InternalServerError {
        Payment|error? payment = findPaymentById(paymentId);
        if payment is error {
            log:printError("DB lookup failed", payment);
            return <http:InternalServerError>{body: {message: "lookup failed"}};
        }
        if payment is Payment {
            return payment;
        }
        return http:NOT_FOUND;
    }


    resource function get byOrder/[string orderId]() returns Payment[]|http:InternalServerError {
        Payment[]|error payments = findPaymentsByOrderId(orderId);
        if payments is error {
            log:printError("DB lookup failed", payments);
            return <http:InternalServerError>{body: {message: "lookup failed"}};
        }
        return payments;
    }

    resource function get health() returns json {
        return {status: "UP", 'service: "payment-service"};
    }
}
