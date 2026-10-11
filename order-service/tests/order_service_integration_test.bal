import ballerina/http;
import ballerina/test;
import dsa612s/order_service.lifecycle;

// These tests exercise the real HTTP service backed by a real MongoDB and
// Kafka, both of which start automatically when the test module's services
// and listeners initialize. They're grouped as "integration" so they can be
// skipped when infra isn't available:
//
//   bal test --disable-groups integration
//
// To run them: start the dependencies, then point the config at them
// (defaults assume the Docker Compose network's "mongo"/"kafka" hostnames,
// which won't resolve from your host machine):
//
//   docker compose up -d zookeeper kafka mongo
//   bal test --groups integration -CmongoHost=localhost -CkafkaBootstrapServers=localhost:29092

final http:Client testClient = check new ("http://localhost:8081/orders");

function sampleOrderRequest(string customerId, string restaurantId) returns lifecycle:CreateOrderRequest => {
    customerId,
    restaurantId,
    items: [{itemId: "item-1", name: "Pizza", quantity: 1, unitPrice: 9.99}]
};

@test:Config {groups: ["integration"]}
function testCreateOrderPersistsAndReturnsCreated() returns error? {
    lifecycle:Order created = check testClient->post("/", sampleOrderRequest("cust-1", "rest-1"));

    test:assertEquals(created.status, lifecycle:CREATED);
    test:assertEquals(created.customerId, "cust-1");
    test:assertEquals(created.totalAmount, 9.99d);

    lifecycle:Order fetched = check testClient->get("/" + created.orderId);
    test:assertEquals(fetched.orderId, created.orderId);
    test:assertEquals(fetched.status, lifecycle:CREATED);
}

@test:Config {groups: ["integration"]}
function testCreateOrderRejectsEmptyItems() returns error? {
    json invalidRequest = {customerId: "cust-2", restaurantId: "rest-2", items: []};
    http:Response response = check testClient->post("/", invalidRequest);
    test:assertEquals(response.statusCode, http:STATUS_BAD_REQUEST);
}

@test:Config {groups: ["integration"]}
function testGetUnknownOrderReturnsNotFound() returns error? {
    http:Response response = check testClient->get("/does-not-exist");
    test:assertEquals(response.statusCode, http:STATUS_NOT_FOUND);
}

@test:Config {groups: ["integration"]}
function testValidStatusTransitionsSucceed() returns error? {
    lifecycle:Order created = check testClient->post("/", sampleOrderRequest("cust-3", "rest-3"));

    lifecycle:Order confirmed = check testClient->put("/" + created.orderId + "/status", {status: "CONFIRMED"});
    test:assertEquals(confirmed.status, lifecycle:CONFIRMED);

    lifecycle:Order preparing = check testClient->put("/" + created.orderId + "/status", {status: "PREPARING"});
    test:assertEquals(preparing.status, lifecycle:PREPARING);
}

@test:Config {groups: ["integration"]}
function testInvalidStatusTransitionReturnsConflict() returns error? {
    lifecycle:Order created = check testClient->post("/", sampleOrderRequest("cust-4", "rest-4"));

    // CREATED -> READY is not a legal jump.
    http:Response response = check testClient->put("/" + created.orderId + "/status", {status: "READY"});
    test:assertEquals(response.statusCode, http:STATUS_CONFLICT);
}

@test:Config {groups: ["integration"]}
function testStatusUpdateOnUnknownOrderReturnsNotFound() returns error? {
    http:Response response = check testClient->put("/does-not-exist/status", {status: "CONFIRMED"});
    test:assertEquals(response.statusCode, http:STATUS_NOT_FOUND);
}

@test:Config {groups: ["integration"]}
function testListOrdersIncludesCreatedOrder() returns error? {
    lifecycle:Order created = check testClient->post("/", sampleOrderRequest("cust-5", "rest-5"));

    lifecycle:Order[] orders = check testClient->get("/");
    boolean found = orders.some(o => o.orderId == created.orderId);
    test:assertTrue(found, "expected the newly created order to appear in the order list");
}
