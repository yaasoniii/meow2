import ballerina/test;

// helper
function createDriver(string id, DriverStatus status) returns Driver {
    return {
        driverId: id,
        name: "Test driver " + id,
        phoneNumber: "0812345678",
        status: status,
        plateNumber: "N  25648 W",
        vehicleType: "Motorcyle - Honda Ace 125"
    };
}

// ----------- selectAvailableDrievr -------------

@test:Config {}
function testSelectAvailableDriverReturnsFirstAvailable(){
    Driver[] drivers = [
        createDriver("DR001",UNAVAILABLE),
        createDriver("DR002", AVAILABLE),
        createDriver("DR003", AVAILABLE)
    ];
    Driver? picked = selectAvailableDriver(drivers);
    test:assertTrue(picked is Driver);
    if picked is Driver{
        test:assertEquals(picked.driverId, "DR002"); 
    }
}

@test:Config {}
function testSelecteAvailableDriverReturnsNilWhenNoneFree(){
    Driver[] drivers = [
        createDriver("DR001", UNAVAILABLE),
        createDriver("DR002",ON_DELIVERY)
    ];
    test:assertTrue(selectAvailableDriver(drivers) is ());
}

@test:Config {}
function testSelectAvailableDriverReturnsNilForEmptyList() {
    Driver[] drivers = [];
    test:assertTrue(selectAvailableDriver(drivers) is ());
}

// ----------- isValidDeliveryStatusTransition -----------
@test:Config {}
function testValidTransitionsFromPending() {
    test:assertTrue(isValidDeliveryStatusTransition(PENDING, ASSIGNED));
    test:assertTrue(isValidDeliveryStatusTransition(PENDING, CANCELLED));
    test:assertFalse(isValidDeliveryStatusTransition(PENDING, DELIVERED));
}

@test:Config {}
function testValidTransitionsFromAssigned(){
    test:assertTrue(isValidDeliveryStatusTransition(ASSIGNED, PICKED_UP));
    test:assertTrue(isValidDeliveryStatusTransition(ASSIGNED, CANCELLED));
    test:assertFalse(isValidDeliveryStatusTransition(ASSIGNED, IN_PROGRESS));
}

@test:Config {}
function testCannotCancelAfterPickup() {
    test:assertFalse(isValidDeliveryStatusTransition(PICKED_UP, CANCELLED));
    test:assertFalse(isValidDeliveryStatusTransition(IN_PROGRESS, CANCELLED));
}

@test:Config {}
function testHappyPathTransitions(){
    test:assertTrue(isValidDeliveryStatusTransition(PICKED_UP, IN_PROGRESS));
    test:assertTrue(isValidDeliveryStatusTransition(IN_PROGRESS, DELIVERED));
}

@test:Config {}
function testTerminalStateHaveNoOutgoingTransitions(){
    test:assertFalse(isValidDeliveryStatusTransition(DELIVERED, PENDING));
    test:assertFalse(isValidDeliveryStatusTransition(CANCELLED, ASSIGNED));
}