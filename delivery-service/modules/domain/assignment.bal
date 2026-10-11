//------------- Driver Assignment Service ------------------//

public isolated function selectAvailableDriver (Driver[] drivers)returns Driver? {
    foreach Driver d in drivers{
        if d.status == AVAILABLE{
            return d;
        }
    }
    return ();
}


// ------------------- Delivery Cycle ---------------------

// Once a driver has PICKED_UP an order, the delivery can not be CANCELLED from this service anymore

public isolated function isValidDeliveryStatusTransition(DeliveryStatus current, DeliveryStatus next) returns boolean {
    match current {
        PENDING =>{
            return next == ASSIGNED || next == CANCELLED;
        }
        ASSIGNED => {
            return next == PICKED_UP || next == CANCELLED;
        }
        PICKED_UP => {
            return next == IN_PROGRESS;
        }
        IN_PROGRESS => {
            return next == DELIVERED;
        }
        _ => {
            return false; // terminal states (DELIVERED, CANCELLED)
        }
    }
}