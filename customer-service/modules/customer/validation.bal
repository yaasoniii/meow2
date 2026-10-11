// Registration / profile validation. Hand-rolled rather than regex-based so
// each rule is obvious from the code and can be unit tested one at a time.

// Email is the unique key for a customer, so it is stored in one canonical
// form: surrounding whitespace removed and lowercased. "Bob@Example.com  " and
// "bob@example.com" must not be able to register twice.
public isolated function normaliseEmail(string email) returns string {
    return email.trim().toLowerAscii();
}

// Deliberately permissive: enough structure to catch typos and obvious junk
// (no "@", no domain dot, embedded spaces) without rejecting legitimate
// addresses that a stricter pattern would refuse.
public isolated function isValidEmail(string email) returns boolean {
    string trimmed = email.trim();
    if trimmed == "" || trimmed.includes(" ") {
        return false;
    }

    int? atIndex = trimmed.indexOf("@");
    if atIndex is () || atIndex == 0 {
        return false; // missing "@", or nothing before it
    }

    string domain = trimmed.substring(atIndex + 1);
    if domain.indexOf("@") !is () {
        return false; // a second "@"
    }

    int? dotIndex = domain.indexOf(".");
    // The domain needs a dot that is neither its first nor its last character,
    // so "a@b", "a@.com" and "a@b." are all rejected.
    return dotIndex !is () && dotIndex != 0 && dotIndex != domain.length() - 1;
}

// Loose E.164: an optional leading "+" then 7-15 digits. Covers the Namibian
// numbers we test with (+264...) as well as plain local numbers.
public isolated function isValidPhone(string phone) returns boolean {
    string trimmed = phone.trim();
    string digits = trimmed.startsWith("+") ? trimmed.substring(1) : trimmed;
    if digits.length() < 7 || digits.length() > 15 {
        return false;
    }
    foreach string:Char c in digits {
        if c < "0" || c > "9" {
            return false;
        }
    }
    return true;
}

public isolated function validateRegistration(RegisterCustomerRequest req) returns ValidationError? {
    if req.fullName.trim() == "" {
        return {fieldName: "fullName", message: "Full name is required"};
    }
    if !isValidEmail(req.email) {
        return {fieldName: "email", message: "A valid email address is required"};
    }
    if !isValidPhone(req.phone) {
        return {fieldName: "phone", message: "Phone must be 7-15 digits, optionally prefixed with '+'"};
    }
    return ();
}

public isolated function validateProfileUpdate(UpdateCustomerRequest req) returns ValidationError? {
    if req.fullName.trim() == "" {
        return {fieldName: "fullName", message: "Full name is required"};
    }
    if !isValidPhone(req.phone) {
        return {fieldName: "phone", message: "Phone must be 7-15 digits, optionally prefixed with '+'"};
    }
    return ();
}

public isolated function validateAddress(AddressRequest req) returns ValidationError? {
    if req.label.trim() == "" {
        return {fieldName: "label", message: "Address label is required (e.g. \"Home\")"};
    }
    if req.street.trim() == "" {
        return {fieldName: "street", message: "Street is required"};
    }
    if req.city.trim() == "" {
        return {fieldName: "city", message: "City is required"};
    }
    if req.postalCode.trim() == "" {
        return {fieldName: "postalCode", message: "Postal code is required"};
    }
    if req.country.trim() == "" {
        return {fieldName: "country", message: "Country is required"};
    }
    return ();
}
