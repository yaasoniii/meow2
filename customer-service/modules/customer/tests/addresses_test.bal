import ballerina/test;

// Exhaustive cover of the saved-address CRUD rules, in particular the
// "exactly one default address" invariant described in addresses.bal.
// Pure logic, so no Mongo or Kafka is needed to run any of this.

function homeRequest() returns AddressRequest => {
    label: "Home",
    street: "12 Independence Avenue",
    city: "Windhoek",
    postalCode: "10005",
    country: "Namibia"
};

function workRequest() returns AddressRequest => {
    label: "Work",
    street: "13 Jackson Kaujeua Street",
    city: "Windhoek",
    postalCode: "10001",
    country: "Namibia"
};

// A customer who already has Home (default) and Work (not default).
function twoAddresses() returns Address[] {
    Address[] addresses = addAddress([], buildAddress("addr-home", homeRequest()));
    return addAddress(addresses, buildAddress("addr-work", workRequest()));
}

// ---------- buildAddress ----------

@test:Config {}
function testBuildAddressTrimsEveryField() {
    AddressRequest req = {
        label: "  Home  ",
        street: "  12 Independence Avenue ",
        city: " Windhoek ",
        postalCode: " 10005 ",
        country: " Namibia ",
        isDefault: true
    };

    Address expected = {
        addressId: "addr-1",
        label: "Home",
        street: "12 Independence Avenue",
        city: "Windhoek",
        postalCode: "10005",
        country: "Namibia",
        isDefault: true
    };
    test:assertEquals(buildAddress("addr-1", req), expected);
}

// ---------- addAddress ----------

@test:Config {}
function testFirstAddressBecomesDefaultEvenWhenNotRequested() {
    Address[] result = addAddress([], buildAddress("addr-home", homeRequest()));

    test:assertEquals(result.length(), 1);
    test:assertTrue(result[0].isDefault, "the first address saved must become the default");
}

@test:Config {}
function testSecondNonDefaultAddressLeavesTheExistingDefaultAlone() {
    Address[] result = twoAddresses();

    test:assertEquals(result.length(), 2);
    test:assertTrue(result[0].isDefault);
    test:assertFalse(result[1].isDefault);
}

@test:Config {}
function testAddingADefaultAddressDemotesThePreviousOne() {
    AddressRequest req = workRequest();
    req.isDefault = true;

    Address[] existing = addAddress([], buildAddress("addr-home", homeRequest()));
    Address[] result = addAddress(existing, buildAddress("addr-work", req));

    test:assertFalse(result[0].isDefault, "the old default must be demoted");
    test:assertTrue(result[1].isDefault);
    test:assertEquals(countDefaults(result), 1);
}

// addAddress copies rather than mutating, so the caller's array is untouched
// if the database write that follows it fails.
@test:Config {}
function testAddAddressDoesNotMutateTheInputList() {
    Address[] original = addAddress([], buildAddress("addr-home", homeRequest()));

    AddressRequest req = workRequest();
    req.isDefault = true;
    Address[] ignored = addAddress(original, buildAddress("addr-work", req));
    test:assertEquals(ignored.length(), 2);

    test:assertEquals(original.length(), 1);
    test:assertTrue(original[0].isDefault, "the caller's list must be left as it was");
}

// ---------- findAddress / defaultAddress ----------

@test:Config {}
function testFindAddressReturnsTheMatchingAddress() {
    Address? found = findAddress(twoAddresses(), "addr-work");
    if found is () {
        test:assertFail("expected addr-work to be found");
    }
    test:assertEquals(found.label, "Work");
}

@test:Config {}
function testFindAddressReturnsNilForAnUnknownId() {
    test:assertTrue(findAddress(twoAddresses(), "addr-nowhere") is ());
}

@test:Config {}
function testDefaultAddressReturnsTheFlaggedAddress() {
    Address? current = defaultAddress(twoAddresses());
    if current is () {
        test:assertFail("expected a default address");
    }
    test:assertEquals(current.addressId, "addr-home");
}

@test:Config {}
function testDefaultAddressIsNilForACustomerWithNoAddresses() {
    Address[] none = [];
    test:assertTrue(defaultAddress(none) is ());
}

// ---------- updateAddress ----------

@test:Config {}
function testUpdateAddressReplacesTheStoredFields() {
    AddressRequest req = workRequest();
    req.street = "20 Sam Nujoma Drive";

    Address[]? result = updateAddress(twoAddresses(), "addr-work", req);
    if result is () {
        test:assertFail("expected addr-work to be updated");
    }

    Address? updated = findAddress(result, "addr-work");
    if updated is () {
        test:assertFail("updated address disappeared from the list");
    }
    test:assertEquals(updated.street, "20 Sam Nujoma Drive");
    test:assertEquals(result.length(), 2, "an update must not add or drop addresses");
}

@test:Config {}
function testUpdateAddressReturnsNilForAnUnknownId() {
    test:assertTrue(updateAddress(twoAddresses(), "addr-nowhere", workRequest()) is ());
}

@test:Config {}
function testUpdatePromotingAnAddressDemotesTheOldDefault() {
    AddressRequest req = workRequest();
    req.isDefault = true;

    Address[]? result = updateAddress(twoAddresses(), "addr-work", req);
    if result is () {
        test:assertFail("expected addr-work to be updated");
    }

    test:assertEquals(defaultAddressId(result), "addr-work");
    test:assertEquals(countDefaults(result), 1);
}

// isDefault: false on the current default is ignored - you switch defaults by
// promoting another address, never by demoting the only one you have.
@test:Config {}
function testUpdateCannotDemoteTheCurrentDefault() {
    AddressRequest req = homeRequest();
    req.isDefault = false;

    Address[]? result = updateAddress(twoAddresses(), "addr-home", req);
    if result is () {
        test:assertFail("expected addr-home to be updated");
    }

    test:assertEquals(defaultAddressId(result), "addr-home");
    test:assertEquals(countDefaults(result), 1);
}

// ---------- removeAddress ----------

@test:Config {}
function testRemoveAddressDropsOnlyTheRequestedAddress() {
    Address[]? result = removeAddress(twoAddresses(), "addr-work");
    if result is () {
        test:assertFail("expected addr-work to be removed");
    }

    test:assertEquals(result.length(), 1);
    test:assertEquals(result[0].addressId, "addr-home");
}

@test:Config {}
function testRemoveAddressReturnsNilForAnUnknownId() {
    test:assertTrue(removeAddress(twoAddresses(), "addr-nowhere") is ());
}

@test:Config {}
function testRemovingANonDefaultAddressLeavesTheDefaultAlone() {
    Address[]? result = removeAddress(twoAddresses(), "addr-work");
    if result is () {
        test:assertFail("expected addr-work to be removed");
    }
    test:assertEquals(defaultAddressId(result), "addr-home");
}

@test:Config {}
function testRemovingTheDefaultPromotesTheFirstRemainingAddress() {
    Address[]? result = removeAddress(twoAddresses(), "addr-home");
    if result is () {
        test:assertFail("expected addr-home to be removed");
    }

    test:assertEquals(defaultAddressId(result), "addr-work");
    test:assertEquals(countDefaults(result), 1);
}

@test:Config {}
function testRemovingTheLastAddressLeavesAnEmptyList() {
    Address[] single = addAddress([], buildAddress("addr-home", homeRequest()));

    Address[]? result = removeAddress(single, "addr-home");
    if result is () {
        test:assertFail("expected addr-home to be removed");
    }
    test:assertEquals(result.length(), 0);
    test:assertTrue(defaultAddress(result) is (), "an empty list has no default");
}

// ---------- helpers ----------

function countDefaults(Address[] addresses) returns int {
    int count = 0;
    foreach Address candidate in addresses {
        if candidate.isDefault {
            count += 1;
        }
    }
    return count;
}

function defaultAddressId(Address[] addresses) returns string {
    Address? current = defaultAddress(addresses);
    return current is () ? "" : current.addressId;
}
