// Pure rules for whether a restaurant can take an order. No database or Kafka
// here, so they are unit tested directly (tests/ordering_test.bal).

// "HH:MM" -> minutes since midnight. Assumes the format was already validated.
isolated function minutesOfDay(string hhmm) returns int {
    int hours = checkpanic int:fromString(hhmm.substring(0, 2));
    int minutes = checkpanic int:fromString(hhmm.substring(3, 5));
    return hours * 60 + minutes;
}

// True when `now` ("HH:MM") falls inside the opening hours. Handles kitchens that
// close after midnight (e.g. 18:00-02:00). Open time inclusive, close time exclusive.
public isolated function isWithinOpeningHours(OpeningHours hours, string now) returns boolean {
    int open = minutesOfDay(hours.openTime);
    int close = minutesOfDay(hours.closeTime);
    int current = minutesOfDay(now);
    if open == close {
        return true; // same open and close time = open all day
    }
    if open < close {
        return current >= open && current < close;
    }
    return current >= open || current < close;
}

// One line of an incoming order, as the restaurant sees it.
public type OrderLine record {|
    string itemId;
    string name;
    int quantity;
|};

// Why the restaurant can't fulfil an order, or () when it can. `menu` holds
// this restaurant's current menu items.
public isolated function rejectionReason(Restaurant r, string now, OrderLine[] lines, MenuItem[] menu)
        returns string? {
    if !r.isOpen {
        return r.name + " is not taking orders right now";
    }
    if !isWithinOpeningHours(r.hours, now) {
        return string `${r.name} is closed (open ${r.hours.openTime}-${r.hours.closeTime})`;
    }
    foreach OrderLine line in lines {
        MenuItem? found = ();
        foreach MenuItem candidate in menu {
            if candidate.itemId == line.itemId {
                found = candidate;
                break;
            }
        }
        if found is () {
            return line.name + " is no longer on the menu";
        }
        MenuItem item = found;
        if !item.available || item.stockCount < line.quantity {
            return string `Not enough ${item.name} in stock (${item.stockCount} left)`;
        }
    }
    return ();
}
