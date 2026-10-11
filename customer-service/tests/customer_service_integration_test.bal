import ballerina/http;
import ballerina/test;
import ballerina/uuid;
import dsa612s/customer_service.customer;

// These tests exercise the real HTTP service backed by a real MongoDB and
// Kafka, both of which start automatically when the test module's services and
// listeners initialize. They're grouped as "integration" so they can be skipped
// when infra isn't available:
//
//   bal test --disable-groups integration
//
// To run them: start the dependencies, then point the config at them (defaults
// assume the Docker Compose network's "mongo"/"kafka" hostnames, which won't
// resolve from your host machine). Configurables that live in a submodule need
// the fully-qualified -C key: <package>.<module>.<name>.
//
//   docker compose -f ../docker-compose.yml up -d zookeeper kafka mongo
//   bal test --groups integration \
//            -Ccustomer_service.messaging.kafkaBootstrapServers=localhost:29092 \
//            -Ccustomer_service.store.mongoHost=localhost

final http:Client testClient = check new ("http://localhost:8082/customers");

// Email is unique in Mongo, so every test registers with a fresh address -
// otherwise a second `bal test` run would collide with the first one's data.
function uniqueEmail() returns string => uuid:createType1AsString() + "@example.com";

function registrationRequest() returns customer:RegisterCustomerRequest => {
    fullName: "Robert Shipanga",
    email: uniqueEmail(),
    phone: "+264811234567"
};

function addressRequest(string label) returns json => {
    label: label,
    street: "12 Independence Avenue",
    city: "Windhoek",
    postalCode: "10005",
    country: "Namibia",
    isDefault: false
};

function registerCustomer() returns customer:Customer|error {
    return testClient->post("/", registrationRequest());
}

// ---------- Registration ----------

@test:Config {groups: ["integration"]}
function testRegisterCustomerPersistsAndReturnsProfile() returns error? {
    customer:RegisterCustomerRequest req = registrationRequest();
    customer:Customer created = check testClient->post("/", req);

    test:assertEquals(created.fullName, "Robert Shipanga");
    test:assertEquals(created.email, req.email);
    test:assertEquals(created.addresses.length(), 0, "a new customer starts with no saved addresses");
    test:assertNotEquals(created.customerId, "");

    customer:Customer fetched = check testClient->get("/" + created.customerId);
    test:assertEquals(fetched.customerId, created.customerId);
    test:assertEquals(fetched.email, req.email);
}

@test:Config {groups: ["integration"]}
function testRegisterCustomerNormalisesEmail() returns error? {
    string email = uniqueEmail();
    json req = {fullName: "Case Test", email: "  " + email.toUpperAscii() + " ", phone: "0811234567"};

    customer:Customer created = check testClient->post("/", req);
    test:assertEquals(created.email, email, "email should be stored trimmed and lowercased");
}

@test:Config {groups: ["integration"]}
function testRegisterCustomerRejectsInvalidEmail() returns error? {
    json req = {fullName: "Bad Email", email: "not-an-email", phone: "0811234567"};

    http:Response response = check testClient->post("/", req);
    test:assertEquals(response.statusCode, http:STATUS_BAD_REQUEST);
}

@test:Config {groups: ["integration"]}
function testRegisterCustomerRejectsInvalidPhone() returns error? {
    json req = {fullName: "Bad Phone", email: uniqueEmail(), phone: "081"};

    http:Response response = check testClient->post("/", req);
    test:assertEquals(response.statusCode, http:STATUS_BAD_REQUEST);
}

@test:Config {groups: ["integration"]}
function testRegisterCustomerRejectsDuplicateEmail() returns error? {
    customer:RegisterCustomerRequest req = registrationRequest();
    customer:Customer _ = check testClient->post("/", req);

    http:Response response = check testClient->post("/", req);
    test:assertEquals(response.statusCode, http:STATUS_CONFLICT);
}

@test:Config {groups: ["integration"]}
function testGetUnknownCustomerReturnsNotFound() returns error? {
    http:Response response = check testClient->get("/does-not-exist");
    test:assertEquals(response.statusCode, http:STATUS_NOT_FOUND);
}

// ---------- Profile updates ----------

@test:Config {groups: ["integration"]}
function testUpdateProfileChangesNameAndPhone() returns error? {
    customer:Customer created = check registerCustomer();

    customer:Customer updated = check testClient->put("/" + created.customerId,
            {fullName: "Robert S.", phone: "0817654321"});
    test:assertEquals(updated.fullName, "Robert S.");
    test:assertEquals(updated.phone, "0817654321");
    test:assertEquals(updated.email, created.email, "email is the identity and must not change");

    customer:Customer fetched = check testClient->get("/" + created.customerId);
    test:assertEquals(fetched.fullName, "Robert S.");
}

@test:Config {groups: ["integration"]}
function testUpdateProfileRejectsInvalidPhone() returns error? {
    customer:Customer created = check registerCustomer();

    http:Response response = check testClient->put("/" + created.customerId,
            {fullName: "Robert S.", phone: "nope"});
    test:assertEquals(response.statusCode, http:STATUS_BAD_REQUEST);
}

// ---------- Saved addresses ----------

@test:Config {groups: ["integration"]}
function testAddressCrudLifecycle() returns error? {
    customer:Customer created = check registerCustomer();
    string base = "/" + created.customerId + "/addresses";

    // First address becomes the default even though isDefault was false.
    customer:Address home = check testClient->post(base, addressRequest("Home"));
    test:assertEquals(home.label, "Home");
    test:assertTrue(home.isDefault, "the first saved address must become the default");

    // Second address does not steal the default.
    customer:Address work = check testClient->post(base, addressRequest("Work"));
    test:assertFalse(work.isDefault);

    customer:Address[] listed = check testClient->get(base);
    test:assertEquals(listed.length(), 2);

    // Promote the second one; the first must be demoted.
    json promote = {
        label: "Work",
        street: "13 Jackson Kaujeua Street",
        city: "Windhoek",
        postalCode: "10001",
        country: "Namibia",
        isDefault: true
    };
    customer:Address promoted = check testClient->put(base + "/" + work.addressId, promote);
    test:assertTrue(promoted.isDefault);
    test:assertEquals(promoted.street, "13 Jackson Kaujeua Street");

    customer:Address[] afterPromotion = check testClient->get(base);
    test:assertEquals(countDefaults(afterPromotion), 1, "exactly one address may be the default");

    // Deleting the default promotes the remaining address.
    http:Response deleteResponse = check testClient->delete(base + "/" + promoted.addressId);
    test:assertEquals(deleteResponse.statusCode, http:STATUS_NO_CONTENT);

    customer:Address[] afterDelete = check testClient->get(base);
    test:assertEquals(afterDelete.length(), 1);
    test:assertTrue(afterDelete[0].isDefault, "the last remaining address must become the default");
}

@test:Config {groups: ["integration"]}
function testAddAddressRejectsMissingFields() returns error? {
    customer:Customer created = check registerCustomer();
    json incomplete = {label: "", street: "", city: "", postalCode: "", country: ""};

    http:Response response =
        check testClient->post("/" + created.customerId + "/addresses", incomplete);
    test:assertEquals(response.statusCode, http:STATUS_BAD_REQUEST);
}

@test:Config {groups: ["integration"]}
function testAddAddressForUnknownCustomerReturnsNotFound() returns error? {
    http:Response response = check testClient->post("/does-not-exist/addresses", addressRequest("Home"));
    test:assertEquals(response.statusCode, http:STATUS_NOT_FOUND);
}

@test:Config {groups: ["integration"]}
function testUpdateUnknownAddressReturnsNotFound() returns error? {
    customer:Customer created = check registerCustomer();

    http:Response response = check testClient->put(
            "/" + created.customerId + "/addresses/does-not-exist", addressRequest("Home"));
    test:assertEquals(response.statusCode, http:STATUS_NOT_FOUND);
}

// ---------- Order history ----------

// The history itself is populated by the Kafka consumer, not by this API, so
// this only asserts the endpoint's contract: an empty list for a customer who
// has never ordered, and a 404 for a customer who doesn't exist.
@test:Config {groups: ["integration"]}
function testOrderHistoryIsEmptyForANewCustomer() returns error? {
    customer:Customer created = check registerCustomer();

    customer:OrderHistoryEntry[] history = check testClient->get("/" + created.customerId + "/orders");
    test:assertEquals(history.length(), 0);
}

@test:Config {groups: ["integration"]}
function testOrderHistoryForUnknownCustomerReturnsNotFound() returns error? {
    http:Response response = check testClient->get("/does-not-exist/orders");
    test:assertEquals(response.statusCode, http:STATUS_NOT_FOUND);
}

// ---------- Deregistration ----------

@test:Config {groups: ["integration"]}
function testDeleteCustomerRemovesTheProfile() returns error? {
    customer:Customer created = check registerCustomer();

    http:Response deleteResponse = check testClient->delete("/" + created.customerId);
    test:assertEquals(deleteResponse.statusCode, http:STATUS_NO_CONTENT);

    http:Response getResponse = check testClient->get("/" + created.customerId);
    test:assertEquals(getResponse.statusCode, http:STATUS_NOT_FOUND);
}

@test:Config {groups: ["integration"]}
function testDeleteUnknownCustomerReturnsNotFound() returns error? {
    http:Response response = check testClient->delete("/does-not-exist");
    test:assertEquals(response.statusCode, http:STATUS_NOT_FOUND);
}

// ---------- Helpers ----------

function countDefaults(customer:Address[] addresses) returns int {
    int count = 0;
    foreach customer:Address candidate in addresses {
        if candidate.isDefault {
            count += 1;
        }
    }
    return count;
}
