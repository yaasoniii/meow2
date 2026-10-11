import ballerina/http;
import ballerina/test;
import ballerina/uuid;

// Integration tests: need Kafka and the payment-db Postgres running (see README).
// Order/customer ids are real UUIDs because that is what the platform uses and
// what the payments table stores.

final http:Client testClient = check new ("http://localhost:8084/payments");

function newPaymentRequest(decimal amount) returns json => {
    orderId: uuid:createType4AsString(),
    customerId: uuid:createType4AsString(),
    amount: amount
};

@test:Config {groups: ["integration"]}
function testInitiatePaymentReturnsAPayment() returns error? {
    json response = check testClient->post("/initiate", newPaymentRequest(49.99));
    test:assertTrue(response.paymentId is string);
    string status = check response.status;
    test:assertTrue(status == "SUCCESS" || status == "FAILED");
}

@test:Config {groups: ["integration"]}
function testGetPaymentStatus() returns error? {
    json created = check testClient->post("/initiate", newPaymentRequest(25.00));
    string paymentId = check created.paymentId;

    json fetched = check testClient->get("/" + paymentId);
    test:assertEquals(check fetched.paymentId, paymentId);
}

@test:Config {groups: ["integration"]}
function testGetUnknownPaymentReturns404() returns error? {
    http:Response notAUuid = check testClient->get("/does-not-exist");
    test:assertEquals(notAUuid.statusCode, 404);

    http:Response unknownUuid = check testClient->get("/" + uuid:createType4AsString());
    test:assertEquals(unknownUuid.statusCode, 404);
}

@test:Config {groups: ["integration"]}
function testNonUuidIdsAreRejected() returns error? {
    http:Response response = check testClient->post("/initiate", {orderId: "order-1", customerId: "cust-1", amount: 10});
    test:assertEquals(response.statusCode, 400);
}

// Retries are allowed until one succeeds; after that the order is paid and
// further attempts get 409.
@test:Config {groups: ["integration"]}
function testRetryUntilPaidThenConflict() returns error? {
    json payload = newPaymentRequest(10.00);
    string orderId = check payload.orderId;

    boolean paid = false;
    foreach int i in 0 ..< 50 {
        json attempt = check testClient->post("/initiate", payload);
        if check attempt.status == "SUCCESS" {
            paid = true;
            break;
        }
    }
    test:assertTrue(paid, "expected at least one success in 50 attempts");

    http:Response again = check testClient->post("/initiate", payload);
    test:assertEquals(again.statusCode, 409);

    json history = check testClient->get("/byOrder/" + orderId);
    test:assertTrue(history is json[]);
}
