import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;
import dsa612s/order_service.lifecycle;
import dsa612s/order_service.messaging;
import dsa612s/order_service.store;

configurable int servicePort = 8081;

listener http:Listener orderListener = new (servicePort);

type HealthStatus record {|
    string status;
    string[] consumedTopics;
|};

// ---------- REST API ----------
service /orders on orderListener {

    // Create a new order -> CREATED, persists to MongoDB, publishes orders.created
    resource function post .(lifecycle:CreateOrderRequest req)
            returns lifecycle:Order|http:BadRequest|http:InternalServerError {
        if req.items.length() == 0 {
            return <http:BadRequest>{body: {message: "Order must contain at least one item"}};
        }

        string id = uuid:createType1AsString();
        string now = time:utcToString(time:utcNow());

        lifecycle:Order newOrder = {
            orderId: id,
            customerId: req.customerId,
            restaurantId: req.restaurantId,
            items: req.items,
            totalAmount: lifecycle:computeOrderTotal(req.items),
            status: lifecycle:CREATED,
            createdAt: now,
            updatedAt: now
        };

        error? saveResult = store:saveOrder(newOrder);
        if saveResult is error {
            log:printError("Failed to persist order", saveResult);
            return <http:InternalServerError>{body: {message: "Failed to save order"}};
        }

        error? publishResult = messaging:publishOrderCreated(newOrder);
        if publishResult is error {
            log:printError("Failed to publish orders.created", publishResult);
            return <http:InternalServerError>{body: {message: "Order saved but event publish failed"}};
        }

        return newOrder;
    }

    // Fetch a single order
    resource function get [string orderId]() returns lifecycle:Order|http:NotFound|http:InternalServerError {
        lifecycle:Order?|error result = store:findOrderById(orderId);
        if result is error {
            log:printError("Failed to fetch order", result);
            return <http:InternalServerError>{body: {message: "Failed to fetch order"}};
        }
        if result is () {
            return <http:NotFound>{body: {message: "Order not found: " + orderId}};
        }
        return result;
    }

    // List orders, newest first. Optional ?customerId= / ?restaurantId= / ?status= filters.
    resource function get .(string? customerId = (), string? restaurantId = (), string? status = ())
            returns lifecycle:Order[]|http:InternalServerError {
        map<json> filter = {};
        if customerId is string {
            filter["customerId"] = customerId;
        }
        if restaurantId is string {
            filter["restaurantId"] = restaurantId;
        }
        if status is string {
            filter["status"] = status;
        }
        lifecycle:Order[]|error result = store:findOrders(filter);
        if result is error {
            log:printError("Failed to list orders", result);
            return <http:InternalServerError>{body: {message: "Failed to list orders"}};
        }
        return result;
    }

    // Advance the order's lifecycle status -> publishes orders.status_updated
    resource function put [string orderId]/status(lifecycle:UpdateStatusRequest req)
            returns lifecycle:Order|http:NotFound|http:Conflict|http:InternalServerError {
        lifecycle:Order?|error existingResult = store:findOrderById(orderId);
        if existingResult is error {
            log:printError("Failed to fetch order for status update", existingResult);
            return <http:InternalServerError>{body: {message: "Failed to fetch order"}};
        }
        if existingResult is () {
            return <http:NotFound>{body: {message: "Order not found: " + orderId}};
        }

        lifecycle:Order current = existingResult;

        if !lifecycle:isValidTransition(current.status, req.status) {
            return <http:Conflict>{
                body: {
                    message: string `Invalid transition from ${current.status} to ${req.status}`
                }
            };
        }

        lifecycle:OrderStatus previousStatus = current.status;
        string now = time:utcToString(time:utcNow());

        error? updateResult = store:applyStatusTransition(orderId, previousStatus, req.status, now);
        if updateResult is error {
            log:printError("Failed to update order status", updateResult);
            return <http:Conflict>{body: {message: "Order status changed concurrently, please retry"}};
        }

        error? publishResult = messaging:publishStatusUpdated(orderId, previousStatus, req.status);
        if publishResult is error {
            log:printError("Failed to publish orders.status_updated", publishResult);
            return <http:InternalServerError>{body: {message: "Status updated but event publish failed"}};
        }

        current.status = req.status;
        current.updatedAt = now;
        return current;
    }
}

// Separate base path so "health" can never be mistaken for an orderId.
service /health on orderListener {

    resource function get .() returns HealthStatus {
        return {status: "UP", consumedTopics: messaging:consumedTopics()};
    }
}
