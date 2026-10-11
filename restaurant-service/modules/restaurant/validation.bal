// Validates a "HH:MM" 24-hour time string.
function isValidTimeOfDay(string time) returns boolean {
    if time.length() != 5 {
        return false;
    }

    string hourPart = time.substring(0, 2);
    string colon = time.substring(2, 3);
    string minutePart = time.substring(3, 5);

    if colon != ":" {
        return false;
    }

    int|error hour = int:fromString(hourPart);
    int|error minute = int:fromString(minutePart);

    if hour is error || minute is error {
        return false;
    }

    if hour < 0 || hour > 23 {
        return false;
    }

    if minute < 0 || minute > 59 {
        return false;
    }

    return true;
}

public function validateRegistration(RegisterRestaurantRequest request) returns ValidationError? {
    if request.name.trim().length() == 0 {
        return {fieldName: "name", message: "Name is required"};
    }

    if request.ownerId.trim().length() == 0 {
        return {fieldName: "ownerId", message: "Owner ID is required"};
    }

    if request.location.trim().length() == 0 {
        return {fieldName: "location", message: "Location is required"};
    }

    if !isValidTimeOfDay(request.hours.openTime) {
        return {fieldName: "hours.openTime", message: "Open time must be in HH:MM format"};
    }

    if !isValidTimeOfDay(request.hours.closeTime) {
        return {fieldName: "hours.closeTime", message: "Close time must be in HH:MM format"};
    }

    return ();
}

public function validateProfileUpdate(UpdateRestaurantRequest request) returns ValidationError? {
    if request.name.trim().length() == 0 {
        return {fieldName: "name", message: "Name is required"};
    }

    if request.location.trim().length() == 0 {
        return {fieldName: "location", message: "Location is required"};
    }

    return ();
}

public function validateHoursUpdate(UpdateHoursRequest request) returns ValidationError? {
    if !isValidTimeOfDay(request.openTime) {
        return {fieldName: "openTime", message: "Open time must be in HH:MM format"};
    }

    if !isValidTimeOfDay(request.closeTime) {
        return {fieldName: "closeTime", message: "Close time must be in HH:MM format"};
    }

    return ();
}

public function validateAddMenuItem(AddMenuItemRequest request) returns ValidationError? {
    if request.name.trim().length() == 0 {
        return {fieldName: "name", message: "Name is required"};
    }

    if request.price <= 0d {
        return {fieldName: "price", message: "Price must be greater than zero"};
    }

    if request.stockCount < 0 {
        return {fieldName: "stockCount", message: "Stock count cannot be negative"};
    }

    return ();
}

public function validateUpdateMenuItem(UpdateMenuItemRequest request) returns ValidationError? {
    string? name = request.name;
    if name is string && name.trim().length() == 0 {
        return {fieldName: "name", message: "Name cannot be blank"};
    }

    decimal? price = request.price;
    if price is decimal && price <= 0d {
        return {fieldName: "price", message: "Price must be greater than zero"};
    }

    int? stockCount = request.stockCount;
    if stockCount is int && stockCount < 0 {
        return {fieldName: "stockCount", message: "Stock count cannot be negative"};
    }

    return ();
}