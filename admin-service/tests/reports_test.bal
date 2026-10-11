function sampleOrders() returns OrderRecord[] => [
    {orderId: "o1", restaurantId: "r1", totalAmount: 100.00, createdAt: "2026-10-05T12:00:00Z", deliveredAt: "2026-10-05T12:30:00Z"},
    {orderId: "o2", restaurantId: "r1", totalAmount: 50.00, createdAt: "2026-10-05T13:00:00Z", deliveredAt: "2026-10-05T13:20:00Z"},
    {orderId: "o3", restaurantId: "r1", totalAmount: 40.00, createdAt: "2026-10-05T14:00:00Z", cancelledAt: "2026-10-05T14:05:00Z"},
    {orderId: "o4", restaurantId: "r2", totalAmount: 60.00, createdAt: "2026-10-05T15:00:00Z", deliveredAt: "2026-10-05T16:10:00Z"},
    {orderId: "o5", restaurantId: "r2", totalAmount: 30.00, createdAt: "2026-10-05T16:00:00Z"},
    {orderId: "x1", deliveredAt: "2026-10-05T12:00:00Z"}
];

@test:Config {}
function testOrdersPerRestaurant() {
    Report report = buildReport("test", "2026-10-05T17:00:00Z", sampleOrders());

    RestaurantStats[] expected = [
        {restaurantId: "r1", totalOrders: 3, deliveredOrders: 2, cancelledOrders: 1, revenue: 150.00d},
        {restaurantId: "r2", totalOrders: 2, deliveredOrders: 1, cancelledOrders: 0, revenue: 60.00d}
    ];
    test:assertEquals(report.restaurants, expected);
}

@test:Config {}
function testDeliveryTimes() {
    Report report = buildReport("test", "2026-10-05T17:00:00Z", sampleOrders());

    test:assertEquals(report.deliveries.completedDeliveries, 3);
    test:assertEquals(report.deliveries.averageMinutes, 40.00d);
    test:assertEquals(report.deliveries.fastestMinutes, 20.00d);
    test:assertEquals(report.deliveries.slowestMinutes, 70.00d);
}

@test:Config {}
function testCancellations() {
    Report report = buildReport("test", "2026-10-05T17:00:00Z", sampleOrders());

    test:assertEquals(report.cancellations.totalOrders, 5);
    test:assertEquals(report.cancellations.cancelledOrders, 1);
    test:assertEquals(report.cancellations.cancellationRate, 20.00d);
}

@test:Config {}
function testCancelledOrderIsNotCountedAsDelivered() {
    OrderRecord[] orders = [
        {orderId: "o1", restaurantId: "r1", totalAmount: 10.00, createdAt: "2026-10-05T12:00:00Z",
            deliveredAt: "2026-10-05T12:30:00Z", cancelledAt: "2026-10-05T12:10:00Z"}
    ];
    Report report = buildReport("test", "2026-10-05T17:00:00Z", orders);

    test:assertEquals(report.restaurants[0].deliveredOrders, 0);
    test:assertEquals(report.restaurants[0].revenue, 0.0d);
    test:assertEquals(report.deliveries.completedDeliveries, 0);
}

@test:Config {}
function testReportWithNoOrders() {
    Report report = buildReport("test", "2026-10-05T17:00:00Z", []);

    test:assertEquals(report.restaurants.length(), 0);
    test:assertEquals(report.deliveries.completedDeliveries, 0);
    test:assertEquals(report.deliveries.averageMinutes, ());
    test:assertEquals(report.cancellations.cancellationRate, 0.0d);
}

@test:Config {}
function testMinutesBetween() {
    test:assertEquals(minutesBetween("2026-10-05T12:00:00Z", "2026-10-05T12:30:00Z"), 30.0d);
    test:assertEquals(minutesBetween("2026-10-05T12:00:00Z", "2026-10-05T12:01:30Z"), 1.5d);
    test:assertEquals(minutesBetween((), "2026-10-05T12:30:00Z"), ());
    test:assertEquals(minutesBetween("2026-10-05T12:30:00Z", "2026-10-05T12:00:00Z"), ());
}
