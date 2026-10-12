import ballerina/http;
import ballerina/log;
import dsa612s/notification_service.messaging;
import dsa612s/notification_service.store;

configurable int servicePort = 8086;

listener http:Listener notificationListener = new (servicePort);

type HealthStatus record {|
    string status;
    string[] consumedTopics;
|};

service /notifications on notificationListener {

    // Newest first. Filter by ?recipientId= (a customer, restaurant or driver id),
    // ?audience= (CUSTOMER / RESTAURANT / DRIVER) and/or ?orderId=; ?limit= caps the count.
    resource function get .(string? recipientId = (), string? audience = (), string? orderId = (),
            int 'limit = 50) returns store:Notification[]|http:BadRequest|http:InternalServerError {
        if 'limit < 1 || 'limit > 500 {
            return <http:BadRequest>{body: {message: "limit must be between 1 and 500"}};
        }
        if audience is string && audience != "CUSTOMER" && audience != "RESTAURANT" && audience != "DRIVER" {
            return <http:BadRequest>{body: {message: "audience must be CUSTOMER, RESTAURANT or DRIVER"}};
        }
        store:Notification[]|error notifications =
            store:listNotifications(recipientId, audience, orderId, 'limit);
        if notifications is error {
            log:printError("Failed to list notifications", notifications);
            return <http:InternalServerError>{body: {message: "Failed to list notifications"}};
        }
        return notifications;
    }
}

service /health on notificationListener {

    resource function get .() returns HealthStatus {
        return {status: "UP", consumedTopics: messaging:consumedTopics()};
    }
}
