import ballerina/test;

// These tests exercise pure, side-effect-free logic only (no Mongo/Kafka
// required), so they always run, with or without Docker up:
//
//   bal test --tests "customer_service.customer:*"

// ---------- normaliseEmail ----------

@test:Config {}
function testNormaliseEmailTrimsAndLowercases() {
    test:assertEquals(normaliseEmail("  Robert@Example.COM "), "robert@example.com");
}

@test:Config {}
function testNormaliseEmailLeavesCanonicalFormUnchanged() {
    test:assertEquals(normaliseEmail("robert@example.com"), "robert@example.com");
}

// ---------- isValidEmail ----------

function validEmailProvider() returns string[][] {
    return [
        ["robert@example.com"],
        ["robert.shipanga@students.nust.na"],
        ["r@a.co"],
        ["first+tag@sub.domain.org"],
        ["  robert@example.com  "] // trimmed before checking
    ];
}

@test:Config {dataProvider: validEmailProvider}
function testIsValidEmailAcceptsRealAddresses(string email) {
    test:assertTrue(isValidEmail(email), string `expected ${email} to be accepted`);
}

function invalidEmailProvider() returns string[][] {
    return [
        [""],
        ["   "],
        ["robert"], // no @
        ["@example.com"], // nothing before the @
        ["robert@example"], // no dot in the domain
        ["robert@.com"], // dot is the first character of the domain
        ["robert@example."], // dot is the last character of the domain
        ["robert@@example.com"], // two @
        ["robert@exa mple.com"] // embedded space
    ];
}

@test:Config {dataProvider: invalidEmailProvider}
function testIsValidEmailRejectsMalformedAddresses(string email) {
    test:assertFalse(isValidEmail(email), string `expected "${email}" to be rejected`);
}

// ---------- isValidPhone ----------

function validPhoneProvider() returns string[][] {
    return [["+264811234567"], ["0811234567"], ["1234567"], ["  +264811234567  "], ["123456789012345"]];
}

@test:Config {dataProvider: validPhoneProvider}
function testIsValidPhoneAcceptsDigitStrings(string phone) {
    test:assertTrue(isValidPhone(phone), string `expected ${phone} to be accepted`);
}

function invalidPhoneProvider() returns string[][] {
    return [
        [""],
        ["123456"], // one digit too short
        ["1234567890123456"], // one digit too long
        ["+"], // plus with no digits
        ["081-123-4567"], // separators aren't allowed
        ["081 123 4567"],
        ["08112345ab"],
        ["++264811234567"]
    ];
}

@test:Config {dataProvider: invalidPhoneProvider}
function testIsValidPhoneRejectsEverythingElse(string phone) {
    test:assertFalse(isValidPhone(phone), string `expected "${phone}" to be rejected`);
}

// ---------- validateRegistration ----------

function validRegistration() returns RegisterCustomerRequest => {
    fullName: "Robert Shipanga",
    email: "robert@example.com",
    phone: "+264811234567"
};

@test:Config {}
function testValidateRegistrationAcceptsAGoodRequest() {
    test:assertTrue(validateRegistration(validRegistration()) is ());
}

@test:Config {}
function testValidateRegistrationRejectsEmptyName() {
    RegisterCustomerRequest req = validRegistration();
    req.fullName = "";

    ValidationError? result = validateRegistration(req);
    if result is () {
        test:assertFail("expected an empty full name to be rejected");
    }
    test:assertEquals(result.fieldName, "fullName");
}

@test:Config {}
function testValidateRegistrationRejectsWhitespaceOnlyName() {
    RegisterCustomerRequest req = validRegistration();
    req.fullName = "   ";

    ValidationError? result = validateRegistration(req);
    if result is () {
        test:assertFail("expected a whitespace-only full name to be rejected");
    }
    test:assertEquals(result.fieldName, "fullName");
}

@test:Config {}
function testValidateRegistrationRejectsBadEmail() {
    RegisterCustomerRequest req = validRegistration();
    req.email = "not-an-email";

    ValidationError? result = validateRegistration(req);
    if result is () {
        test:assertFail("expected a malformed email to be rejected");
    }
    test:assertEquals(result.fieldName, "email");
}

@test:Config {}
function testValidateRegistrationRejectsBadPhone() {
    RegisterCustomerRequest req = validRegistration();
    req.phone = "call-me";

    ValidationError? result = validateRegistration(req);
    if result is () {
        test:assertFail("expected a malformed phone number to be rejected");
    }
    test:assertEquals(result.fieldName, "phone");
}

// Name is checked before email, and email before phone, so a request with
// several problems reports the first one rather than an arbitrary one.
@test:Config {}
function testValidateRegistrationReportsTheFirstProblem() {
    RegisterCustomerRequest req = {fullName: "", email: "nope", phone: "nope"};

    ValidationError? result = validateRegistration(req);
    if result is () {
        test:assertFail("expected an invalid request to be rejected");
    }
    test:assertEquals(result.fieldName, "fullName");
}

// ---------- validateProfileUpdate ----------

@test:Config {}
function testValidateProfileUpdateAcceptsAGoodRequest() {
    UpdateCustomerRequest req = {fullName: "Robert S.", phone: "0811234567"};
    test:assertTrue(validateProfileUpdate(req) is ());
}

@test:Config {}
function testValidateProfileUpdateRejectsBadPhone() {
    UpdateCustomerRequest req = {fullName: "Robert S.", phone: "081"};

    ValidationError? result = validateProfileUpdate(req);
    if result is () {
        test:assertFail("expected a too-short phone number to be rejected");
    }
    test:assertEquals(result.fieldName, "phone");
}

// ---------- validateAddress ----------

function validAddressRequest() returns AddressRequest => {
    label: "Home",
    street: "12 Independence Avenue",
    city: "Windhoek",
    postalCode: "10005",
    country: "Namibia"
};

@test:Config {}
function testValidateAddressAcceptsACompleteAddress() {
    test:assertTrue(validateAddress(validAddressRequest()) is ());
}

function missingAddressFieldProvider() returns [string, AddressRequest][] {
    AddressRequest noLabel = validAddressRequest();
    noLabel.label = "";
    AddressRequest noStreet = validAddressRequest();
    noStreet.street = "  ";
    AddressRequest noCity = validAddressRequest();
    noCity.city = "";
    AddressRequest noPostalCode = validAddressRequest();
    noPostalCode.postalCode = "";
    AddressRequest noCountry = validAddressRequest();
    noCountry.country = "";

    return [
        ["label", noLabel],
        ["street", noStreet],
        ["city", noCity],
        ["postalCode", noPostalCode],
        ["country", noCountry]
    ];
}

@test:Config {dataProvider: missingAddressFieldProvider}
function testValidateAddressRejectsMissingFields(string expectedField, AddressRequest req) {
    ValidationError? result = validateAddress(req);
    if result is () {
        test:assertFail(string `expected a missing ${expectedField} to be rejected`);
    }
    test:assertEquals(result.fieldName, expectedField);
}
