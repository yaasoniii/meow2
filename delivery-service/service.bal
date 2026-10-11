import ballerina/http;
import ballerina/log;
import ballerina/uuid;
import dsa612s/delivery_service.domain;
import dsa612s/delivery_service.messaging;
import dsa612s/delivery_service.store;

configurable int servicePort = 8085;

listener http:Listener deliveryListener = new (servicePort);

type HealthStatus record {|
    string status;
    string[] consumedTopics;
|};

// ---------- Drivers ----------
service /drivers on deliveryListener {

    // Register a driver. They start AVAILABLE, so a waiting delivery may be
    // handed to them immediately - the response reflects that.
    resource function post .(domain:RegisterDriverRequest req)
            returns domain:Driver|http:BadRequest|http:InternalServerError {
        string? invalid = domain:validateDriverRegistration(req);
        if invalid is string {
            return <http:BadRequest>{body: {message: invalid}};
        }

        domain:Driver driver = {
            driverId: uuid:createType1AsString(),
            name: req.name.trim(),
            phoneNumber: req.phoneNumber.trim(),
            status: domain:AVAILABLE,
            plateNumber: req.plateNumber.trim(),
            vehicleType: req.vehicleType.trim()
        };
        error? saveResult = store:saveDriver(driver);
        if saveResult is error {
            log:printError("Failed to save driver", saveResult);
            return <http:InternalServerError>{body: {message: "Failed to register driver"}};
        }

        assignWaitingDeliveries();
        domain:Driver|http:NotFound|http:InternalServerError reloaded = loadDriver(driver.driverId);
        return reloaded is domain:Driver ? reloaded : driver;
    }

    resource function get .() returns domain:Driver[]|http:InternalServerError {
        domain:Driver[]|error drivers = store:findAllDrivers();
        if drivers is error {
            log:printError("Failed to list drivers", drivers);
            return <http:InternalServerError>{body: {message: "Failed to list drivers"}};
        }
        return drivers;
    }

    resource function get [string driverId]() returns domain:Driver|http:NotFound|http:InternalServerError {
        return loadDriver(driverId);
    }

    // A driver toggles themselves AVAILABLE / UNAVAILABLE. ON_DELIVERY is only
    // ever set by assignment, and a driver mid-delivery can't go off shift.
    resource function put [string driverId]/status(domain:UpdateDriverStatusRequest req)
            returns domain:Driver|http:BadRequest|http:NotFound|http:Conflict|http:InternalServerError {
        if req.status == domain:ON_DELIVERY {
            return <http:BadRequest>{body: {message: "ON_DELIVERY is set automatically when a delivery is assigned"}};
        }

        domain:Driver|http:NotFound|http:InternalServerError existing = loadDriver(driverId);
        if existing !is domain:Driver {
            return existing;
        }
        if existing.status == domain:ON_DELIVERY {
            return <http:Conflict>{body: {message: "Driver is on a delivery; finish it first"}};
        }

        error? updateResult = store:updateDriverStatus(driverId, req.status, ());
        if updateResult is error {
            log:printError("Failed to update driver status", updateResult);
            return <http:InternalServerError>{body: {message: "Failed to update driver status"}};
        }
        if req.status == domain:AVAILABLE {
            assignWaitingDeliveries();
        }
        return loadDriver(driverId);
    }
}

// ---------- Deliveries ----------
service /deliveries on deliveryListener {

    // Newest first. Optional ?orderId= / ?driverId= / ?status= filters.
    resource function get .(string? orderId = (), string? driverId = (), string? status = ())
            returns domain:Delivery[]|http:InternalServerError {
        map<json> filter = {};
        if orderId is string {
            filter["orderId"] = orderId;
        }
        if driverId is string {
            filter["driverId"] = driverId;
        }
        if status is string {
            filter["status"] = status;
        }
        domain:Delivery[]|error deliveries = store:findDeliveries(filter);
        if deliveries is error {
            log:printError("Failed to list deliveries", deliveries);
            return <http:InternalServerError>{body: {message: "Failed to list deliveries"}};
        }
        return deliveries;
    }

    resource function get [string deliveryId]() returns domain:Delivery|http:NotFound|http:InternalServerError {
        return loadDelivery(deliveryId);
    }

    // Retry driver assignment for a PENDING delivery (e.g. after drivers came online).
    resource function post [string deliveryId]/assign()
            returns domain:Delivery|http:NotFound|http:Conflict|http:InternalServerError {
        domain:Delivery|http:NotFound|http:InternalServerError existing = loadDelivery(deliveryId);
        if existing !is domain:Delivery {
            return existing;
        }
        if existing.status != domain:PENDING {
            return <http:Conflict>{body: {message: string `Delivery is ${existing.status}, not PENDING`}};
        }

        boolean|error assigned = messaging:tryAssignDriver(existing);
        if assigned is error {
            log:printError("Failed to assign driver", assigned);
            return <http:InternalServerError>{body: {message: "Failed to assign driver"}};
        }
        if !assigned {
            return <http:Conflict>{body: {message: "No driver is available right now"}};
        }
        return loadDelivery(deliveryId);
    }

    // Driver progress: PICKED_UP -> IN_PROGRESS -> DELIVERED (or CANCELLED before pickup).
    resource function put [string deliveryId]/status(domain:UpdateDeliveryStatusRequest req)
            returns domain:Delivery|http:BadRequest|http:NotFound|http:Conflict|http:InternalServerError {
        if req.status == domain:ASSIGNED {
            return <http:BadRequest>{body: {message: "Use POST /deliveries/{id}/assign to assign a driver"}};
        }

        domain:Delivery|http:NotFound|http:InternalServerError existing = loadDelivery(deliveryId);
        if existing !is domain:Delivery {
            return existing;
        }
        if !domain:isValidDeliveryStatusTransition(existing.status, req.status) {
            return <http:Conflict>{
                body: {message: string `Invalid transition from ${existing.status} to ${req.status}`}
            };
        }

        domain:Delivery|error updated = messaging:transitionDelivery(existing, req.status);
        if updated is error {
            log:printError("Failed to update delivery status", updated);
            return <http:Conflict>{body: {message: "Delivery status changed concurrently, please retry"}};
        }
        return updated;
    }
}

service /health on deliveryListener {

    resource function get .() returns HealthStatus {
        return {status: "UP", consumedTopics: messaging:consumedTopics()};
    }
}

// ---------- Helpers ----------

// Best effort: a failure here shouldn't fail the request that freed a driver.
isolated function assignWaitingDeliveries() {
    error? result = messaging:assignPendingDeliveries();
    if result is error {
        log:printError("Failed to assign pending deliveries", result);
    }
}

isolated function loadDriver(string driverId) returns domain:Driver|http:NotFound|http:InternalServerError {
    domain:Driver?|error result = store:findDriverById(driverId);
    if result is error {
        log:printError("Failed to fetch driver", result);
        return <http:InternalServerError>{body: {message: "Failed to fetch driver"}};
    }
    if result is () {
        return <http:NotFound>{body: {message: "Driver not found: " + driverId}};
    }
    return result;
}

isolated function loadDelivery(string deliveryId) returns domain:Delivery|http:NotFound|http:InternalServerError {
    domain:Delivery?|error result = store:findDeliveryById(deliveryId);
    if result is error {
        log:printError("Failed to fetch delivery", result);
        return <http:InternalServerError>{body: {message: "Failed to fetch delivery"}};
    }
    if result is () {
        return <http:NotFound>{body: {message: "Delivery not found: " + deliveryId}};
    }
    return result;
}
