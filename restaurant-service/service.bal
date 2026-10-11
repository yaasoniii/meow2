import ballerina/http;
import ballerina/time;
import ballerina/uuid;
import restaurant_service.restaurant;
import restaurant_service.store;
import restaurant_service.messaging;

configurable int servicePort = 8083;

listener http:Listener restaurantListener = new (servicePort);

service /restaurants on restaurantListener {

    resource function post .(restaurant:RegisterRestaurantRequest req) returns restaurant:Restaurant|http:BadRequest|http:InternalServerError {
        restaurant:ValidationError? validationError = restaurant:validateRegistration(req);
        if validationError is restaurant:ValidationError {
            return badRequest(validationError);
        }

        string now = time:utcToString(time:utcNow());
        restaurant:Restaurant newRestaurant = {
            restaurantId: uuid:createType1AsString(),
            ownerId: req.ownerId,
            name: req.name,
            description: req.description,
            location: req.location,
            hours: req.hours,
            isOpen: true,
            createdAt: now,
            updatedAt: now
        };

        error? saveResult = store:saveRestaurant(newRestaurant);
        if saveResult is error {
            return <http:InternalServerError>{body: {message: "Failed to save restaurant"}};
        }

        return newRestaurant;
    }

    resource function get .() returns restaurant:Restaurant[]|http:InternalServerError {
        restaurant:Restaurant[]|error result = store:findAllRestaurants();
        if result is error {
            return <http:InternalServerError>{body: {message: "Failed to load restaurants"}};
        }
        return result;
    }

    resource function get [string restaurantId]() returns restaurant:Restaurant|http:NotFound|http:InternalServerError {
        return loadRestaurant(restaurantId);
    }

    resource function put [string restaurantId](restaurant:UpdateRestaurantRequest req)
            returns restaurant:Restaurant|http:BadRequest|http:NotFound|http:InternalServerError {
        restaurant:ValidationError? validationError = restaurant:validateProfileUpdate(req);
        if validationError is restaurant:ValidationError {
            return badRequest(validationError);
        }

        restaurant:Restaurant|http:NotFound|http:InternalServerError existing = loadRestaurant(restaurantId);
        if existing is http:NotFound || existing is http:InternalServerError {
            return existing;
        }

        string now = time:utcToString(time:utcNow());
        error? updateResult = store:updateRestaurantProfile(restaurantId, req, now);
        if updateResult is error {
            return <http:InternalServerError>{body: {message: "Failed to update restaurant"}};
        }

        return loadRestaurant(restaurantId);
    }

    resource function delete [string restaurantId]() returns http:Ok|http:InternalServerError {
        error? deleteResult = store:deleteRestaurant(restaurantId);
        if deleteResult is error {
            return <http:InternalServerError>{body: {message: "Failed to delete restaurant"}};
        }
        return <http:Ok>{};
    }

    resource function put [string restaurantId]/hours(restaurant:UpdateHoursRequest req)
            returns restaurant:Restaurant|http:BadRequest|http:NotFound|http:InternalServerError {
        restaurant:ValidationError? validationError = restaurant:validateHoursUpdate(req);
        if validationError is restaurant:ValidationError {
            return badRequest(validationError);
        }

        restaurant:Restaurant|http:NotFound|http:InternalServerError existing = loadRestaurant(restaurantId);
        if existing is http:NotFound || existing is http:InternalServerError {
            return existing;
        }

        string now = time:utcToString(time:utcNow());
        restaurant:OpeningHours hours = {openTime: req.openTime, closeTime: req.closeTime};
        error? updateResult = store:updateRestaurantHours(restaurantId, hours, now);
        if updateResult is error {
            return <http:InternalServerError>{body: {message: "Failed to update hours"}};
        }

        return loadRestaurant(restaurantId);
    }

    resource function get [string restaurantId]/menu() returns restaurant:MenuItem[]|http:InternalServerError {
        restaurant:MenuItem[]|error result = store:findMenuByRestaurant(restaurantId);
        if result is error {
            return <http:InternalServerError>{body: {message: "Failed to load menu"}};
        }
        return result;
    }

    resource function post [string restaurantId]/menu(restaurant:AddMenuItemRequest req)
            returns restaurant:MenuItem|http:BadRequest|http:InternalServerError {
        restaurant:ValidationError? validationError = restaurant:validateAddMenuItem(req);
        if validationError is restaurant:ValidationError {
            return badRequest(validationError);
        }

        restaurant:MenuItem newItem = {
            itemId: uuid:createType1AsString(),
            restaurantId: restaurantId,
            name: req.name,
            description: req.description,
            price: req.price,
            stockCount: req.stockCount,
            available: req.stockCount > 0
        };

        error? saveResult = store:saveMenuItem(newItem);
        if saveResult is error {
            return <http:InternalServerError>{body: {message: "Failed to save menu item"}};
        }

        return newItem;
    }

    resource function put [string restaurantId]/menu/[string itemId](restaurant:UpdateMenuItemRequest req)
            returns restaurant:MenuItem|http:BadRequest|http:NotFound|http:InternalServerError {
        restaurant:ValidationError? validationError = restaurant:validateUpdateMenuItem(req);
        if validationError is restaurant:ValidationError {
            return badRequest(validationError);
        }

        restaurant:MenuItem|http:NotFound|http:InternalServerError existing = loadMenuItem(itemId);
        if existing is http:NotFound || existing is http:InternalServerError {
            return existing;
        }

        error? updateResult = store:updateMenuItem(itemId, req);
        if updateResult is error {
            return <http:InternalServerError>{body: {message: "Failed to update menu item"}};
        }

        return loadMenuItem(itemId);
    }

    resource function delete [string restaurantId]/menu/[string itemId]() returns http:Ok|http:InternalServerError {
        error? deleteResult = store:deleteMenuItem(itemId);
        if deleteResult is error {
            return <http:InternalServerError>{body: {message: "Failed to delete menu item"}};
        }
        return <http:Ok>{};
    }
}

type HealthStatus record {|
    string status;
    string[] consumedTopics;
|};

service /health on restaurantListener {
    resource function get .() returns HealthStatus {
        return {
            status: "UP",
            consumedTopics: messaging:consumedTopics()
        };
    }
}

function loadRestaurant(string restaurantId) returns restaurant:Restaurant|http:NotFound|http:InternalServerError {
    restaurant:Restaurant|error? result = store:findRestaurantById(restaurantId);
    if result is error {
        return <http:InternalServerError>{body: {message: "Failed to load restaurant"}};
    }
    if result is () {
        return restaurantNotFound(restaurantId);
    }
    return result;
}

function loadMenuItem(string itemId) returns restaurant:MenuItem|http:NotFound|http:InternalServerError {
    restaurant:MenuItem|error? result = store:findMenuItemById(itemId);
    if result is error {
        return <http:InternalServerError>{body: {message: "Failed to load menu item"}};
    }
    if result is () {
        return itemNotFound(itemId);
    }
    return result;
}

function badRequest(restaurant:ValidationError err) returns http:BadRequest {
    return {body: {fieldName: err.fieldName, message: err.message}};
}

function restaurantNotFound(string restaurantId) returns http:NotFound {
    return {body: {message: "Restaurant not found: " + restaurantId}};
}

function itemNotFound(string itemId) returns http:NotFound {
    return {body: {message: "Menu item not found: " + itemId}};
}