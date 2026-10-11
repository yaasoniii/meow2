// In-memory notification inbox. Persistence is planned for later; until then
// the consumer replays the topics from the beginning on every start (see
// consumer.bal), which rebuilds this state after a restart.

const int MAX_NOTIFICATIONS = 1000;

isolated Notification[] notifications = [];

// orderId -> customerId, learned from orders.created so later events (which
// only carry orderId) can still be addressed to the right customer.
isolated map<string> orderCustomers = {};

isolated function rememberCustomer(string orderId, string customerId) {
    lock {
        orderCustomers[orderId] = customerId;
    }
}

isolated function customerFor(string orderId) returns string? {
    lock {
        return orderCustomers[orderId];
    }
}

isolated function addNotification(Notification notification) {
    lock {
        notifications.push(notification.clone());
        if notifications.length() > MAX_NOTIFICATIONS {
            _ = notifications.shift();
        }
    }
}

// Newest first, optionally filtered by customer and/or order.
public isolated function listNotifications(string? customerId, string? orderId, int 'limit)
        returns Notification[] {
    lock {
        Notification[] matching = from Notification n in notifications
            where (customerId is () || n.customerId == customerId) && (orderId is () || n.orderId == orderId)
            order by n.timestamp descending
            limit 'limit
            select n;
        return matching.clone();
    }
}
