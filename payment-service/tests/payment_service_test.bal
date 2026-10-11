import ballerina/test;
import ballerina/http;

http:Client testClient = check new ("http://localhost:8083/payments");

@test:Config {}
function testInitiatePaymentSucceeds() returns error? {
    json payload = {orderId: "order-1", customerId: "cust-1", amount: 49.99};
    json response = check testClient->post("/initiate", payload);
    test:assertTrue(response.paymentId is string);
    test:assertTrue(response.status is string);
}

@test:Config {}
function testGetPaymentStatus() returns error? {
    json payload = {orderId: "order-3", customerId: "cust-3", amount: 25.00};
    json created = check testClient->post("/initiate", payload);
    string paymentId = check created.paymentId;

    json fetched = check testClient->get("/" + paymentId);
    test:assertEquals(check fetched.paymentId, paymentId);
}

@test:Config {}
function testGetUnknownPaymentReturns404() returns error? {
    http:Response response = check testClient->get("/does-not-exist");
    test:assertEquals(response.statusCode, 404);
}

@test:Config {}
function testRetriedPaymentGetsNewId() returns error? {
    json payload = {orderId: "order-2", customerId: "cust-2", amount: 10.00};
    json first = check testClient->post("/initiate", payload);
    json second = check testClient->post("/initiate", payload);
    test:assertNotEquals(check first.paymentId, check second.paymentId);

    json history = check testClient->get("/byOrder/order-2");
    test:assertTrue(history is json[]);
}
