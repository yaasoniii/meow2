import ballerina/log;
import ballerina/time;
import dsa612s/delivery_service.domain;
import dsa612s/delivery_service.store;

// Delivery workflows shared by the Kafka consumer and the REST API. They live in
// this module (not service.bal) because the consumer needs them too, and they
// publish events, so they sit next to the producer.

// Tries to give a PENDING delivery a driver. Returns false when nobody is free.
public isolated function tryAssignDriver(domain:Delivery delivery) returns boolean|error {
    domain:Driver[] candidates = check store:fetchAvailableDrivers();
    while true {
        domain:Driver? picked = domain:selectAvailableDriver(candidates);
        if picked is () {
            return false;
        }
        final string driverId = picked.driverId;

        if !check store:claimDriver(driverId, delivery.deliveryId) {
            // Another delivery claimed this driver between the fetch and the claim.
            candidates = candidates.filter(d => d.driverId != driverId);
            continue;
        }

        string now = time:utcToString(time:utcNow());
        error? moved = store:applyDeliveryStatusTransition(delivery.deliveryId, domain:PENDING, domain:ASSIGNED,
                now, driverId);
        if moved is error {
            // The delivery itself changed meanwhile (e.g. cancelled) - give the driver back.
            check store:updateDriverStatus(driverId, domain:AVAILABLE, ());
            return moved;
        }

        check publishDeliveryAssigned(delivery.deliveryId, delivery.orderId, driverId);
        check publishDeliveryStatusUpdated(delivery.deliveryId, delivery.orderId, driverId, domain:PENDING,
                domain:ASSIGNED);
        log:printInfo("Assigned driver", deliveryId = delivery.deliveryId, driverId = driverId);
        return true;
    }
}

// Hands waiting deliveries to free drivers, oldest first. Called whenever a
// driver may have become available.
public isolated function assignPendingDeliveries() returns error? {
    domain:Delivery[] pending = check store:findPendingDeliveries();
    foreach domain:Delivery delivery in pending {
        if !check tryAssignDriver(delivery) {
            return; // no more free drivers
        }
    }
}

// Applies an already-validated transition plus its side effects: the event, and
// freeing the driver when the delivery ends.
public isolated function transitionDelivery(domain:Delivery current, domain:DeliveryStatus next)
        returns domain:Delivery|error {
    string now = time:utcToString(time:utcNow());
    check store:applyDeliveryStatusTransition(current.deliveryId, current.status, next, now);

    string? driverId = current.driverId;
    check publishDeliveryStatusUpdated(current.deliveryId, current.orderId, driverId, current.status, next);

    if driverId is string && (next == domain:DELIVERED || next == domain:CANCELLED) {
        if next == domain:DELIVERED {
            check publishDeliveryCompleted(current.deliveryId, current.orderId, driverId);
        }
        check store:updateDriverStatus(driverId, domain:AVAILABLE, ());
        error? reassigned = assignPendingDeliveries();
        if reassigned is error {
            log:printError("Failed to assign pending deliveries", reassigned);
        }
    }

    domain:Delivery updated = current.clone();
    updated.status = next;
    updated.updatedAt = now;
    return updated;
}
