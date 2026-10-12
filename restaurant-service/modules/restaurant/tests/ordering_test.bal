import ballerina/test;

function testRestaurant() returns Restaurant => {
    restaurantId: "r1", ownerId: "o1", name: "Kapana Corner", description: "", location: "Windhoek",
    hours: {openTime: "08:00", closeTime: "22:00"}, isOpen: true, createdAt: "", updatedAt: ""
};

function testMenu() returns MenuItem[] => [
    {itemId: "i1", restaurantId: "r1", name: "Kapana", description: "", price: 45, stockCount: 5, available: true},
    {itemId: "i2", restaurantId: "r1", name: "Vetkoek", description: "", price: 30, stockCount: 0, available: false}
];

function hoursProvider() returns [string, string, string, boolean][] {
    return [
        ["08:00", "22:00", "08:00", true], // opening minute is open
        ["08:00", "22:00", "12:30", true],
        ["08:00", "22:00", "21:59", true],
        ["08:00", "22:00", "22:00", false], // closing minute is closed
        ["08:00", "22:00", "07:59", false],
        ["18:00", "02:00", "23:30", true], // past midnight
        ["18:00", "02:00", "01:00", true],
        ["18:00", "02:00", "03:00", false],
        ["00:00", "00:00", "13:00", true] // all day
    ];
}

@test:Config {dataProvider: hoursProvider}
function testIsWithinOpeningHours(string open, string close, string now, boolean expected) {
    test:assertEquals(isWithinOpeningHours({openTime: open, closeTime: close}, now), expected,
            string `${now} in ${open}-${close}`);
}

@test:Config {}
function testAcceptsAnOrderItCanFulfil() {
    test:assertEquals(rejectionReason(testRestaurant(), "12:00", [{itemId: "i1", name: "Kapana", quantity: 5}],
            testMenu()), ());
}

@test:Config {}
function testRejectsWhenPaused() {
    Restaurant r = testRestaurant();
    r.isOpen = false;
    test:assertTrue(rejectionReason(r, "12:00", [{itemId: "i1", name: "Kapana", quantity: 1}], testMenu()) is string);
}

@test:Config {}
function testRejectsOutsideOpeningHours() {
    string? reason = rejectionReason(testRestaurant(), "23:00", [{itemId: "i1", name: "Kapana", quantity: 1}],
            testMenu());
    test:assertEquals(reason, "Kapana Corner is closed (open 08:00-22:00)");
}

@test:Config {}
function testRejectsInsufficientStock() {
    test:assertTrue(rejectionReason(testRestaurant(), "12:00", [{itemId: "i1", name: "Kapana", quantity: 6}],
            testMenu()) is string);
}

@test:Config {}
function testRejectsSoldOutItem() {
    test:assertTrue(rejectionReason(testRestaurant(), "12:00", [{itemId: "i2", name: "Vetkoek", quantity: 1}],
            testMenu()) is string);
}

@test:Config {}
function testRejectsUnknownItem() {
    test:assertEquals(rejectionReason(testRestaurant(), "12:00", [{itemId: "nope", name: "Ghost", quantity: 1}],
            testMenu()), "Ghost is no longer on the menu");
}
