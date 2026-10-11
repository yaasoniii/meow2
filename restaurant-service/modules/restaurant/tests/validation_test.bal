import ballerina/test;

@test:Config {
    dataProvider: validRegistrationProvider
}
function testValidRegistration(RegisterRestaurantRequest request) {
    ValidationError? result = validateRegistration(request);
    test:assertTrue(result is (), "expected valid registration to pass");
}

function validRegistrationProvider() returns RegisterRestaurantRequest[][] {
    return [
        [{
            ownerId: "OWNER001",
            name: "Windhoek Grill",
            description: "Local grill house",
            location: "Windhoek",
            hours: {openTime: "08:00", closeTime: "20:00"}
        }]
    ];
}

@test:Config {
    dataProvider: invalidRegistrationProvider
}
function testInvalidRegistration(RegisterRestaurantRequest request, string expectedField) {
    ValidationError? result = validateRegistration(request);
    test:assertTrue(result is ValidationError, "expected validation to fail");
    if result is ValidationError {
        test:assertEquals(result.fieldName, expectedField);
    }
}

function invalidRegistrationProvider() returns [RegisterRestaurantRequest, string][] {
    return [
        [{ownerId: "", name: "Name", description: "d", location: "Windhoek", hours: {openTime: "08:00", closeTime: "20:00"}}, "ownerId"],
        [{ownerId: "OWNER001", name: "", description: "d", location: "Windhoek", hours: {openTime: "08:00", closeTime: "20:00"}}, "name"],
        [{ownerId: "OWNER001", name: "Name", description: "d", location: "", hours: {openTime: "08:00", closeTime: "20:00"}}, "location"],
        [{ownerId: "OWNER001", name: "Name", description: "d", location: "Windhoek", hours: {openTime: "8:00", closeTime: "20:00"}}, "hours.openTime"],
        [{ownerId: "OWNER001", name: "Name", description: "d", location: "Windhoek", hours: {openTime: "08:00", closeTime: "25:00"}}, "hours.closeTime"]
    ];
}

@test:Config {
    dataProvider: hoursUpdateProvider
}
function testHoursUpdate(UpdateHoursRequest request, boolean expectedValid) {
    ValidationError? result = validateHoursUpdate(request);
    if expectedValid {
        test:assertTrue(result is (), "expected valid hours to pass");
    } else {
        test:assertTrue(result is ValidationError, "expected invalid hours to fail");
    }
}

function hoursUpdateProvider() returns [UpdateHoursRequest, boolean][] {
    return [
        [{openTime: "09:00", closeTime: "21:00"}, true],
        [{openTime: "9:00", closeTime: "21:00"}, false],
        [{openTime: "09:00", closeTime: "2100"}, false],
        [{openTime: "24:00", closeTime: "21:00"}, false],
        [{openTime: "09:00", closeTime: "21:60"}, false]
    ];
}

@test:Config {
    dataProvider: addMenuItemProvider
}
function testAddMenuItem(AddMenuItemRequest request, boolean expectedValid) {
    ValidationError? result = validateAddMenuItem(request);
    if expectedValid {
        test:assertTrue(result is (), "expected valid menu item to pass");
    } else {
        test:assertTrue(result is ValidationError, "expected invalid menu item to fail");
    }
}

function addMenuItemProvider() returns [AddMenuItemRequest, boolean][] {
    return [
        [{name: "Cheeseburger", description: "Beef burger", price: 65.0d, stockCount: 20}, true],
        [{name: "", description: "Beef burger", price: 65.0d, stockCount: 20}, false],
        [{name: "Cheeseburger", description: "Beef burger", price: 0d, stockCount: 20}, false],
        [{name: "Cheeseburger", description: "Beef burger", price: -5.0d, stockCount: 20}, false],
        [{name: "Cheeseburger", description: "Beef burger", price: 65.0d, stockCount: -1}, false]
    ];
}

@test:Config {
    dataProvider: updateMenuItemProvider
}
function testUpdateMenuItem(UpdateMenuItemRequest request, boolean expectedValid) {
    ValidationError? result = validateUpdateMenuItem(request);
    if expectedValid {
        test:assertTrue(result is (), "expected valid update to pass");
    } else {
        test:assertTrue(result is ValidationError, "expected invalid update to fail");
    }
}

function updateMenuItemProvider() returns [UpdateMenuItemRequest, boolean][] {
    return [
        [{}, true],
        [{name: "New Name"}, true],
        [{name: "  "}, false],
        [{price: 10.0d}, true],
        [{price: 0d}, false],
        [{stockCount: 5}, true],
        [{stockCount: -3}, false]
    ];
}