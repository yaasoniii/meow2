import ballerinax/mongodb;
import restaurant_service.restaurant;

configurable string mongoHost = "localhost";
configurable int mongoPort = 27017;
configurable string mongoDatabase = "restaurant_service";
configurable string mongoUsername = "";
configurable string mongoPassword = "";
configurable string mongoAuthDatabase = "admin";

function buildConnectionConfig() returns mongodb:ConnectionConfig {
    mongodb:ConnectionParameters connectionParams = {
        serverAddress: {
            host: mongoHost,
            port: mongoPort
        }
    };

    if mongoUsername.trim().length() > 0 {
        connectionParams.auth = <mongodb:ScramSha256AuthCredential>{
            username: mongoUsername,
            password: mongoPassword,
            database: mongoAuthDatabase
        };
    }

    return {
        connection: connectionParams
    };
}

final mongodb:Client mongoClient = check new (buildConnectionConfig());

function restaurantsCollection() returns mongodb:Collection|error {
    mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
    return db->getCollection("restaurants");
}

function menuItemsCollection() returns mongodb:Collection|error {
    mongodb:Database db = check mongoClient->getDatabase(mongoDatabase);
    return db->getCollection("menu_items");
}

public function ensureIndexes() returns error? {
    mongodb:Collection restaurants = check restaurantsCollection();
    check restaurants->createIndex({restaurantId: 1}, {unique: true});

    mongodb:Collection menuItems = check menuItemsCollection();
    check menuItems->createIndex({itemId: 1}, {unique: true});
    check menuItems->createIndex({restaurantId: 1}, {unique: false});
}

public function saveRestaurant(restaurant:Restaurant r) returns error? {
    mongodb:Collection restaurants = check restaurantsCollection();
    check restaurants->insertOne(r);
}

public function findRestaurantById(string restaurantId) returns restaurant:Restaurant|error? {
    mongodb:Collection restaurants = check restaurantsCollection();
    return check restaurants->findOne({restaurantId: restaurantId});
}

public function findAllRestaurants() returns restaurant:Restaurant[]|error {
    mongodb:Collection restaurants = check restaurantsCollection();
    stream<restaurant:Restaurant, error?> resultStream = check restaurants->find({});
    restaurant:Restaurant[] results = [];
    check resultStream.forEach(function(restaurant:Restaurant r) {
        results.push(r);
    });
    return results;
}

public function updateRestaurantProfile(string restaurantId, restaurant:UpdateRestaurantRequest req, string updatedAt) returns error? {
    mongodb:Collection restaurants = check restaurantsCollection();
    mongodb:Update update = {
        set: {
            name: req.name,
            description: req.description,
            location: req.location,
            updatedAt: updatedAt
        }
    };
    _ = check restaurants->updateOne({restaurantId: restaurantId}, update);
}

public function updateRestaurantHours(string restaurantId, restaurant:OpeningHours hours, string updatedAt) returns error? {
    mongodb:Collection restaurants = check restaurantsCollection();
    mongodb:Update update = {
        set: {
            hours: hours,
            updatedAt: updatedAt
        }
    };
    _ = check restaurants->updateOne({restaurantId: restaurantId}, update);
}

public function deleteRestaurant(string restaurantId) returns error? {
    mongodb:Collection restaurants = check restaurantsCollection();
    _ = check restaurants->deleteOne({restaurantId: restaurantId});

    mongodb:Collection menuItems = check menuItemsCollection();
    _ = check menuItems->deleteMany({restaurantId: restaurantId});
}

public function saveMenuItem(restaurant:MenuItem item) returns error? {
    mongodb:Collection menuItems = check menuItemsCollection();
    check menuItems->insertOne(item);
}

public function findMenuItemById(string itemId) returns restaurant:MenuItem|error? {
    mongodb:Collection menuItems = check menuItemsCollection();
    return check menuItems->findOne({itemId: itemId});
}

public function findMenuByRestaurant(string restaurantId) returns restaurant:MenuItem[]|error {
    mongodb:Collection menuItems = check menuItemsCollection();
    stream<restaurant:MenuItem, error?> resultStream = check menuItems->find({restaurantId: restaurantId});
    restaurant:MenuItem[] results = [];
    check resultStream.forEach(function(restaurant:MenuItem item) {
        results.push(item);
    });
    return results;
}

public function updateMenuItem(string itemId, restaurant:UpdateMenuItemRequest req) returns error? {
    mongodb:Collection menuItems = check menuItemsCollection();

    map<json> setFields = {};
    string? name = req.name;
    if name is string {
        setFields["name"] = name;
    }
    string? description = req.description;
    if description is string {
        setFields["description"] = description;
    }
    decimal? price = req.price;
    if price is decimal {
        setFields["price"] = price;
    }
    int? stockCount = req.stockCount;
    if stockCount is int {
        setFields["stockCount"] = stockCount;
    }
    boolean? available = req.available;
    if available is boolean {
        setFields["available"] = available;
    }

    if setFields.length() == 0 {
        return;
    }

    mongodb:Update update = {set: setFields};
    _ = check menuItems->updateOne({itemId: itemId}, update);
}

public function deleteMenuItem(string itemId) returns error? {
    mongodb:Collection menuItems = check menuItemsCollection();
    _ = check menuItems->deleteOne({itemId: itemId});
}

// Called only by the Kafka consumer when an order comes in. Floors stock
// at 0 and auto-marks the item unavailable once it hits 0. Returns false
// (not an error) when the item doesn't belong to this restaurant, so the
// consumer can log-and-continue instead of failing the whole batch.
public function decrementStock(string restaurantId, string itemId, int quantity) returns boolean|error {
    mongodb:Collection menuItems = check menuItemsCollection();
    restaurant:MenuItem? item = check menuItems->findOne({itemId: itemId, restaurantId: restaurantId});

    if item is () {
        return false;
    }

    int newStock = item.stockCount - quantity;
    if newStock < 0 {
        newStock = 0;
    }

    mongodb:Update update = {
        set: {
            stockCount: newStock,
            available: newStock > 0
        }
    };
    _ = check menuItems->updateOne({itemId: itemId}, update);
    return true;
}