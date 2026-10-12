import ballerina/time;

// One order as pieced together from events. Every field except orderId is
// optional because the events can arrive in any order across topics.
type OrderRecord record {|
    string orderId;
    string restaurantId?;
    string customerId?;
    decimal totalAmount?;
    string status?;
    string paymentStatus?;
    string driverId?;
    string createdAt?;
    string updatedAt?;
    string deliveredAt?;
    string cancelledAt?;
|};

type PlatformStats record {|
    int totalOrders;
    map<int> ordersByStatus;
    int activeOrders; // not yet delivered or cancelled
    decimal deliveredRevenue; // total of delivered orders
    decimal averageOrderValue;
    int paymentsSucceeded;
    int paymentsFailed;
    int driversAssigned; // orders that have had a driver assigned
    int completedDeliveries;
    decimal? averageDeliveryMinutes;
|};

type RestaurantStats record {|
    string restaurantId;
    int totalOrders;
    int deliveredOrders;
    int cancelledOrders;
    decimal revenue; // total of delivered orders
|};

type DeliveryStats record {|
    int completedDeliveries;
    decimal? averageMinutes;
    decimal? fastestMinutes;
    decimal? slowestMinutes;
|};

type CancellationStats record {|
    int totalOrders;
    int cancelledOrders;
    decimal cancellationRate; 
|};

type Report record {|
    string reportId;
    string generatedAt;
    RestaurantStats[] restaurants;
    DeliveryStats deliveries;
    CancellationStats cancellations;
|};

function buildReport(string reportId, string generatedAt, OrderRecord[] allOrders) returns Report {
    OrderRecord[] orders = from OrderRecord o in allOrders
        where o?.createdAt is string
        select o;

    return {
        reportId: reportId,
        generatedAt: generatedAt,
        restaurants: restaurantStats(orders),
        deliveries: deliveryStats(orders),
        cancellations: cancellationStats(orders)
    };
}

function buildStats(OrderRecord[] allOrders) returns PlatformStats {
    OrderRecord[] orders = from OrderRecord o in allOrders
        where o?.createdAt is string
        select o;

    map<int> byStatus = {};
    int active = 0;
    decimal orderValueTotal = 0;
    int succeeded = 0;
    int failed = 0;
    int assigned = 0;
    foreach OrderRecord o in orders {
        string status = o?.status ?: "UNKNOWN";
        byStatus[status] = (byStatus[status] ?: 0) + 1;
        if !isCancelled(o) && !isDelivered(o) {
            active += 1;
        }
        orderValueTotal += o?.totalAmount ?: 0.0d;
        if o?.paymentStatus == "SUCCESS" {
            succeeded += 1;
        } else if o?.paymentStatus == "FAILED" {
            failed += 1;
        }
        if o?.driverId is string {
            assigned += 1;
        }
    }

    RestaurantStats[] perRestaurant = restaurantStats(orders);
    decimal revenue = 0;
    foreach RestaurantStats r in perRestaurant {
        revenue += r.revenue;
    }
    DeliveryStats deliveries = deliveryStats(orders);

    return {
        totalOrders: orders.length(),
        ordersByStatus: byStatus,
        activeOrders: active,
        deliveredRevenue: revenue,
        averageOrderValue: orders.length() > 0 ? (orderValueTotal / <decimal>orders.length()).round(2) : 0,
        paymentsSucceeded: succeeded,
        paymentsFailed: failed,
        driversAssigned: assigned,
        completedDeliveries: deliveries.completedDeliveries,
        averageDeliveryMinutes: deliveries.averageMinutes
    };
}

function isCancelled(OrderRecord o) returns boolean {
    return o?.cancelledAt is string;
}

function isDelivered(OrderRecord o) returns boolean {
    return o?.deliveredAt is string && !isCancelled(o);
}

function restaurantStats(OrderRecord[] orders) returns RestaurantStats[] {
    map<RestaurantStats> byRestaurant = {};

    foreach OrderRecord o in orders {
        string id = o?.restaurantId ?: "unknown";
        RestaurantStats? existing = byRestaurant[id];
        RestaurantStats stats;
        if existing is RestaurantStats {
            stats = existing;
        } else {
            stats = {restaurantId: id, totalOrders: 0, deliveredOrders: 0, cancelledOrders: 0, revenue: 0};
            byRestaurant[id] = stats;
        }

        stats.totalOrders += 1;
        if isCancelled(o) {
            stats.cancelledOrders += 1;
        } else if isDelivered(o) {
            stats.deliveredOrders += 1;
            stats.revenue += o?.totalAmount ?: 0.0d;
        }
    }

    return from RestaurantStats s in byRestaurant
        order by s.totalOrders descending, s.restaurantId ascending
        select s;
}

function deliveryStats(OrderRecord[] orders) returns DeliveryStats {
    decimal[] times = [];
    int completed = 0;
    foreach OrderRecord o in orders {
        if isDelivered(o) {
            completed += 1;
            decimal? minutes = minutesBetween(o?.createdAt, o?.deliveredAt);
            if minutes is decimal {
                times.push(minutes);
            }
        }
    }

    if times.length() == 0 {
        return {completedDeliveries: completed, averageMinutes: (), fastestMinutes: (), slowestMinutes: ()};
    }

    decimal total = 0;
    decimal fastest = times[0];
    decimal slowest = times[0];
    foreach decimal t in times {
        total += t;
        if t < fastest {
            fastest = t;
        }
        if t > slowest {
            slowest = t;
        }
    }

    return {
        completedDeliveries: completed,
        averageMinutes: (total / <decimal>times.length()).round(2),
        fastestMinutes: fastest.round(2),
        slowestMinutes: slowest.round(2)
    };
}

function cancellationStats(OrderRecord[] orders) returns CancellationStats {
    int cancelled = 0;
    foreach OrderRecord o in orders {
        if isCancelled(o) {
            cancelled += 1;
        }
    }

    decimal rate = 0;
    if orders.length() > 0 {
        rate = (<decimal>cancelled * 100.0d / <decimal>orders.length()).round(2);
    }
    return {totalOrders: orders.length(), cancelledOrders: cancelled, cancellationRate: rate};
}

function minutesBetween(string? startTime, string? endTime) returns decimal? {
    if startTime is () || endTime is () {
        return ();
    }
    time:Utc|error startUtc = time:utcFromString(startTime);
    time:Utc|error endUtc = time:utcFromString(endTime);
    if startUtc is error || endUtc is error {
        return ();
    }
    decimal seconds = time:utcDiffSeconds(endUtc, startUtc);
    if seconds < 0.0d {
        return ();
    }
    return seconds / 60.0d;
}
