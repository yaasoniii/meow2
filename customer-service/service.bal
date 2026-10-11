import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;
import dsa612s/customer_service.customer;
import dsa612s/customer_service.messaging;
import dsa612s/customer_service.store;

configurable int servicePort = 8082;

listener http:Listener customerListener = new (servicePort);

type HealthStatus record {|
    string status;
    string[] consumedTopics;
|};

// ---------- REST API ----------
service /customers on customerListener {

    // Register a new customer. Email is the natural identity for a person, so a
    // second registration with the same address is a 409 rather than a new row.
    resource function post .(customer:RegisterCustomerRequest req)
            returns customer:Customer|http:BadRequest|http:Conflict|http:InternalServerError {
        customer:ValidationError? validation = customer:validateRegistration(req);
        if validation is customer:ValidationError {
            return badRequest(validation);
        }

        string email = customer:normaliseEmail(req.email);

        customer:Customer?|error duplicate = store:findCustomerByEmail(email);
        if duplicate is error {
            log:printError("Failed to check for an existing customer", duplicate);
            return <http:InternalServerError>{body: {message: "Failed to register customer"}};
        }
        if duplicate is customer:Customer {
            return <http:Conflict>{body: {message: "A customer with this email already exists"}};
        }

        string now = time:utcToString(time:utcNow());
        customer:Customer newCustomer = {
            customerId: uuid:createType1AsString(),
            fullName: req.fullName.trim(),
            email: email,
            phone: req.phone.trim(),
            addresses: [],
            createdAt: now,
            updatedAt: now
        };

        error? saveResult = store:saveCustomer(newCustomer);
        if saveResult is error {
            // The unique index on email also lands here if two registrations
            // raced past the duplicate check above.
            log:printError("Failed to persist customer", saveResult);
            return <http:InternalServerError>{body: {message: "Failed to register customer"}};
        }

        log:printInfo("Registered customer", customerId = newCustomer.customerId);
        return newCustomer;
    }

    // List every registered customer
    resource function get .() returns customer:Customer[]|http:InternalServerError {
        customer:Customer[]|error result = store:findAllCustomers();
        if result is error {
            log:printError("Failed to list customers", result);
            return <http:InternalServerError>{body: {message: "Failed to list customers"}};
        }
        return result;
    }

    // Fetch one customer's profile, saved addresses included
    resource function get [string customerId]()
            returns customer:Customer|http:NotFound|http:InternalServerError {
        customer:Customer|http:NotFound|http:InternalServerError existing = loadCustomer(customerId);
        return existing;
    }

    // Update the editable parts of a profile. Email is the identity (unique
    // index in Mongo) so it isn't changeable here.
    resource function put [string customerId](customer:UpdateCustomerRequest req)
            returns customer:Customer|http:BadRequest|http:NotFound|http:InternalServerError {
        customer:ValidationError? validation = customer:validateProfileUpdate(req);
        if validation is customer:ValidationError {
            return badRequest(validation);
        }

        customer:Customer|http:NotFound|http:InternalServerError existing = loadCustomer(customerId);
        if existing !is customer:Customer {
            return existing;
        }

        string now = time:utcToString(time:utcNow());
        string fullName = req.fullName.trim();
        string phone = req.phone.trim();

        error? updateResult = store:updateCustomerProfile(customerId, fullName, phone, now);
        if updateResult is error {
            log:printError("Failed to update customer profile", updateResult);
            return <http:InternalServerError>{body: {message: "Failed to update customer"}};
        }

        customer:Customer updated = existing;
        updated.fullName = fullName;
        updated.phone = phone;
        updated.updatedAt = now;
        return updated;
    }

    // Deregister a customer and drop the order history we hold for them
    resource function delete [string customerId]()
            returns http:NoContent|http:NotFound|http:InternalServerError {
        boolean|error deleted = store:deleteCustomer(customerId);
        if deleted is error {
            log:printError("Failed to delete customer", deleted);
            return <http:InternalServerError>{body: {message: "Failed to delete customer"}};
        }
        if !deleted {
            return customerNotFound(customerId);
        }

        error? historyResult = store:deleteOrderHistoryForCustomer(customerId);
        if historyResult is error {
            // The customer is already gone, so this is not worth failing the
            // request over - but it does leave orphaned history rows behind.
            log:printError("Deleted customer but failed to clear their order history", historyResult,
                    customerId = customerId);
        }

        log:printInfo("Deleted customer", customerId = customerId);
        return <http:NoContent>{};
    }

    // ---------- Saved delivery addresses ----------

    resource function get [string customerId]/addresses()
            returns customer:Address[]|http:NotFound|http:InternalServerError {
        customer:Customer|http:NotFound|http:InternalServerError existing = loadCustomer(customerId);
        if existing !is customer:Customer {
            return existing;
        }
        return existing.addresses;
    }

    // Add a saved address. The first one a customer saves always becomes their
    // default, whether or not isDefault was set - see modules/customer.
    resource function post [string customerId]/addresses(customer:AddressRequest req)
            returns customer:Address|http:BadRequest|http:NotFound|http:InternalServerError {
        customer:ValidationError? validation = customer:validateAddress(req);
        if validation is customer:ValidationError {
            return badRequest(validation);
        }

        customer:Customer|http:NotFound|http:InternalServerError existing = loadCustomer(customerId);
        if existing !is customer:Customer {
            return existing;
        }

        string addressId = uuid:createType1AsString();
        customer:Address[] updated =
            customer:addAddress(existing.addresses, customer:buildAddress(addressId, req));

        http:InternalServerError? saveError = persistAddresses(customerId, updated);
        if saveError is http:InternalServerError {
            return saveError;
        }

        customer:Address? saved = customer:findAddress(updated, addressId);
        if saved is () {
            return <http:InternalServerError>{body: {message: "Failed to save address"}};
        }
        return saved;
    }

    // Replace a saved address. isDefault: true promotes it; isDefault: false on
    // the current default is ignored, since a customer with addresses must
    // always have exactly one default.
    resource function put [string customerId]/addresses/[string addressId](customer:AddressRequest req)
            returns customer:Address|http:BadRequest|http:NotFound|http:InternalServerError {
        customer:ValidationError? validation = customer:validateAddress(req);
        if validation is customer:ValidationError {
            return badRequest(validation);
        }

        customer:Customer|http:NotFound|http:InternalServerError existing = loadCustomer(customerId);
        if existing !is customer:Customer {
            return existing;
        }

        customer:Address[]? updated = customer:updateAddress(existing.addresses, addressId, req);
        if updated is () {
            return addressNotFound(addressId);
        }

        http:InternalServerError? saveError = persistAddresses(customerId, updated);
        if saveError is http:InternalServerError {
            return saveError;
        }

        customer:Address? saved = customer:findAddress(updated, addressId);
        if saved is () {
            return <http:InternalServerError>{body: {message: "Failed to save address"}};
        }
        return saved;
    }

    // Delete a saved address. Removing the default promotes the first remaining
    // address so the customer is never left without one.
    resource function delete [string customerId]/addresses/[string addressId]()
            returns http:NoContent|http:NotFound|http:InternalServerError {
        customer:Customer|http:NotFound|http:InternalServerError existing = loadCustomer(customerId);
        if existing !is customer:Customer {
            return existing;
        }

        customer:Address[]? remaining = customer:removeAddress(existing.addresses, addressId);
        if remaining is () {
            return addressNotFound(addressId);
        }

        http:InternalServerError? saveError = persistAddresses(customerId, remaining);
        if saveError is http:InternalServerError {
            return saveError;
        }
        return <http:NoContent>{};
    }

    // ---------- Order history ----------

    // Read-only: this collection is built entirely from the Order Service's
    // Kafka events (modules/messaging/consumer.bal), never from this API.
    resource function get [string customerId]/orders()
            returns customer:OrderHistoryEntry[]|http:NotFound|http:InternalServerError {
        customer:Customer|http:NotFound|http:InternalServerError existing = loadCustomer(customerId);
        if existing !is customer:Customer {
            return existing;
        }

        customer:OrderHistoryEntry[]|error history = store:findOrderHistoryByCustomer(customerId);
        if history is error {
            log:printError("Failed to read order history", history, customerId = customerId);
            return <http:InternalServerError>{body: {message: "Failed to read order history"}};
        }
        return history;
    }
}

// Separate base path so the literal "health" segment can never be confused with
// a customerId in /customers/{customerId}. Also gives Docker Compose something
// cheap to healthcheck.
service /health on customerListener {

    resource function get .() returns HealthStatus {
        return {status: "UP", consumedTopics: messaging:consumedTopics()};
    }
}

// ---------- Shared helpers ----------
//
// Nearly every resource above starts by loading the customer and answering 404
// or 500 if that fails, so that shape is factored out here rather than repeated
// nine times. `existing !is customer:Customer` in the callers means "it's
// already an error response - pass it straight back".

isolated function loadCustomer(string customerId)
        returns customer:Customer|http:NotFound|http:InternalServerError {
    customer:Customer?|error result = store:findCustomerById(customerId);
    if result is error {
        log:printError("Failed to fetch customer", result, customerId = customerId);
        return <http:InternalServerError>{body: {message: "Failed to fetch customer"}};
    }
    if result is () {
        return customerNotFound(customerId);
    }
    return result;
}

isolated function persistAddresses(string customerId, customer:Address[] addresses)
        returns http:InternalServerError? {
    error? result = store:replaceAddresses(customerId, addresses, time:utcToString(time:utcNow()));
    if result is error {
        log:printError("Failed to save addresses", result, customerId = customerId);
        return <http:InternalServerError>{body: {message: "Failed to save addresses"}};
    }
    return ();
}

isolated function badRequest(customer:ValidationError validation) returns http:BadRequest {
    return {body: {message: validation.message, fieldName: validation.fieldName}};
}

isolated function customerNotFound(string customerId) returns http:NotFound {
    return {body: {message: "Customer not found: " + customerId}};
}

isolated function addressNotFound(string addressId) returns http:NotFound {
    return {body: {message: "Address not found: " + addressId}};
}
