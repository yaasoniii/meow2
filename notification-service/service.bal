import ballerina/http;
import dsa612s/notification_service.messaging;

configurable int servicePort = 8086;

listener http:Listener notificationListener = new (servicePort);

type HealthStatus record {|
    string status;
    string[] consumedTopics;
|};

service /notifications on notificationListener {

    // Newest first. Filter with ?customerId= and/or ?orderId=; ?limit= caps the count.
    resource function get .(string? customerId = (), string? orderId = (), int 'limit = 50)
            returns messaging:Notification[] {
        return messaging:listNotifications(customerId, orderId, 'limit);
    }
}

service /health on notificationListener {

    resource function get .() returns HealthStatus {
        return {status: "UP", consumedTopics: messaging:consumedTopics()};
    }
}
