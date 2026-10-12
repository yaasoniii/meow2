import ballerina/test;

// These tests exercise pure, side-effect-free logic only (no Mongo/Kafka required),
// so `bal test --disable-groups integration` (or even a plain `bal test` with no
// infra running) will always be able to run them.

// ---------- isValidTransition: exhaustive 7x7 transition matrix ----------
// The expected values below are written independently of isValidTransition's
// implementation, from the state diagram in the README, so this actually
// verifies the logic rather than restating it.

function transitionDataProvider() returns [OrderStatus, OrderStatus, boolean][] {
    return [
        // From CREATED
        [CREATED, CREATED, false],
        [CREATED, CONFIRMED, true],
        [CREATED, PREPARING, false],
        [CREATED, READY, false],
        [CREATED, OUT_FOR_DELIVERY, false],
        [CREATED, DELIVERED, false],
        [CREATED, CANCELLED, true],
        // From CONFIRMED
        [CONFIRMED, CREATED, false],
        [CONFIRMED, CONFIRMED, false],
        [CONFIRMED, PREPARING, true],
        [CONFIRMED, READY, false],
        [CONFIRMED, OUT_FOR_DELIVERY, false],
        [CONFIRMED, DELIVERED, false],
        [CONFIRMED, CANCELLED, true],
        // From PREPARING
        [PREPARING, CREATED, false],
        [PREPARING, CONFIRMED, false],
        [PREPARING, PREPARING, false],
        [PREPARING, READY, true],
        [PREPARING, OUT_FOR_DELIVERY, false],
        [PREPARING, DELIVERED, false],
        [PREPARING, CANCELLED, true],
        // From READY (cannot be cancelled anymore - food is already made)
        [READY, CREATED, false],
        [READY, CONFIRMED, false],
        [READY, PREPARING, false],
        [READY, READY, false],
        [READY, OUT_FOR_DELIVERY, true],
        [READY, DELIVERED, false],
        [READY, CANCELLED, false],
        // From OUT_FOR_DELIVERY
        [OUT_FOR_DELIVERY, CREATED, false],
        [OUT_FOR_DELIVERY, CONFIRMED, false],
        [OUT_FOR_DELIVERY, PREPARING, false],
        [OUT_FOR_DELIVERY, READY, false],
        [OUT_FOR_DELIVERY, OUT_FOR_DELIVERY, false],
        [OUT_FOR_DELIVERY, DELIVERED, true],
        [OUT_FOR_DELIVERY, CANCELLED, false],
        // From DELIVERED (terminal)
        [DELIVERED, CREATED, false],
        [DELIVERED, CONFIRMED, false],
        [DELIVERED, PREPARING, false],
        [DELIVERED, READY, false],
        [DELIVERED, OUT_FOR_DELIVERY, false],
        [DELIVERED, DELIVERED, false],
        [DELIVERED, CANCELLED, false],
        // From CANCELLED (terminal)
        [CANCELLED, CREATED, false],
        [CANCELLED, CONFIRMED, false],
        [CANCELLED, PREPARING, false],
        [CANCELLED, READY, false],
        [CANCELLED, OUT_FOR_DELIVERY, false],
        [CANCELLED, DELIVERED, false],
        [CANCELLED, CANCELLED, false]
    ];
}

@test:Config {dataProvider: transitionDataProvider}
function testIsValidTransition(OrderStatus 'from, OrderStatus to, boolean expected) {
    boolean actual = isValidTransition('from, to);
    test:assertEquals(actual, expected, string `expected isValidTransition(${'from}, ${to}) == ${expected}`);
}

// ---------- computeOrderTotal ----------

@test:Config {}
function testComputeOrderTotalSumsAllItems() {
    OrderItem[] items = [
        {itemId: "item-1", name: "Burger", quantity: 2, unitPrice: 5.50},
        {itemId: "item-2", name: "Fries", quantity: 1, unitPrice: 2.25}
    ];
    test:assertEquals(computeOrderTotal(items), 13.25d);
}

@test:Config {}
function testComputeOrderTotalSingleItem() {
    OrderItem[] items = [
        {itemId: "item-1", name: "Pizza", quantity: 3, unitPrice: 9.99}
    ];
    test:assertEquals(computeOrderTotal(items), 29.97d);
}

@test:Config {}
function testComputeOrderTotalEmptyListIsZero() {
    OrderItem[] items = [];
    test:assertEquals(computeOrderTotal(items), 0d);
}

// ---------- validateCreateOrder ----------

function validOrderRequest() returns CreateOrderRequest => {
    customerId: "cust-1",
    restaurantId: "rest-1",
    items: [{itemId: "item-1", name: "Pizza", quantity: 2, unitPrice: 9.99}]
};

@test:Config {}
function testValidateCreateOrderAcceptsAGoodRequest() {
    test:assertEquals(validateCreateOrder(validOrderRequest()), ());
}

function invalidOrderProvider() returns [string, CreateOrderRequest][] {
    CreateOrderRequest noCustomer = validOrderRequest();
    noCustomer.customerId = " ";
    CreateOrderRequest noRestaurant = validOrderRequest();
    noRestaurant.restaurantId = "";
    CreateOrderRequest noItems = validOrderRequest();
    noItems.items = [];
    CreateOrderRequest zeroQuantity = validOrderRequest();
    zeroQuantity.items[0].quantity = 0;
    CreateOrderRequest hugeQuantity = validOrderRequest();
    hugeQuantity.items[0].quantity = MAX_ITEM_QUANTITY + 1;
    CreateOrderRequest freeItem = validOrderRequest();
    freeItem.items[0].unitPrice = 0;
    CreateOrderRequest blankItem = validOrderRequest();
    blankItem.items[0].itemId = "";
    return [
        ["blank customerId", noCustomer],
        ["blank restaurantId", noRestaurant],
        ["no items", noItems],
        ["zero quantity", zeroQuantity],
        ["quantity above the maximum", hugeQuantity],
        ["zero price", freeItem],
        ["blank itemId", blankItem]
    ];
}

@test:Config {dataProvider: invalidOrderProvider}
function testValidateCreateOrderRejects(string description, CreateOrderRequest req) {
    test:assertTrue(validateCreateOrder(req) is string, "expected rejection for " + description);
}
