public type OpeningHours record {|
    string openTime;
    string closeTime;
|};

public type Restaurant record {|
    string restaurantId;
    string ownerId;
    string name;
    string description;
    string location;
    OpeningHours hours;
    boolean isOpen;
    string createdAt;
    string updatedAt;
|};

public type MenuItem record {|
    string itemId;
    string restaurantId;
    string name;
    string description;
    decimal price;
    int stockCount;
    boolean available;
|};

public type RegisterRestaurantRequest record {|
    string ownerId;
    string name;
    string description;
    string location;
    OpeningHours hours;
|};

public type UpdateRestaurantRequest record {|
    string name;
    string description;
    string location;
|};

public type UpdateAvailabilityRequest record {|
    boolean isOpen;
|};

public type UpdateHoursRequest record {|
    string openTime;
    string closeTime;
|};

public type AddMenuItemRequest record {|
    string name;
    string description;
    decimal price;
    int stockCount;
|};

public type UpdateMenuItemRequest record {|
    string name?;
    string description?;
    decimal price?;
    int stockCount?;
    boolean available?;
|};

public type ValidationError record {|
    string fieldName;
    string message;
|};