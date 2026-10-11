// Saved-address CRUD, written as pure functions over an Address[].
//
// A customer's addresses live embedded in their Mongo document, so "update one
// address" is really "rewrite the whole array". Keeping that rewrite here - with
// no database in sight - means the one rule that is easy to get wrong,
//
//     a customer with at least one address has exactly one default address,
//
// is enforced in a single place and can be unit tested exhaustively without
// Mongo or Kafka running. The service layer just persists whatever array comes
// back from these functions.

public isolated function buildAddress(string addressId, AddressRequest req) returns Address {
    return {
        addressId: addressId,
        label: req.label.trim(),
        street: req.street.trim(),
        city: req.city.trim(),
        postalCode: req.postalCode.trim(),
        country: req.country.trim(),
        isDefault: req.isDefault
    };
}

public isolated function findAddress(Address[] addresses, string addressId) returns Address? {
    foreach Address candidate in addresses {
        if candidate.addressId == addressId {
            return candidate;
        }
    }
    return ();
}

public isolated function defaultAddress(Address[] addresses) returns Address? {
    foreach Address candidate in addresses {
        if candidate.isDefault {
            return candidate;
        }
    }
    return ();
}

// The very first address a customer saves becomes their default whether they
// asked for it or not - otherwise a customer could have addresses but no
// default, and the Delivery Service would have nowhere to deliver to.
public isolated function addAddress(Address[] existing, Address newAddress) returns Address[] {
    boolean makeDefault = newAddress.isDefault || existing.length() == 0;
    Address[] result = cloneAddresses(existing, makeDefault);

    Address added = newAddress.clone();
    added.isDefault = makeDefault;
    result.push(added);
    return result;
}

// Returns () when addressId isn't in the list, so the caller can map that
// straight onto a 404 rather than inventing an error type.
public isolated function updateAddress(Address[] existing, string addressId, AddressRequest req)
        returns Address[]? {
    Address? target = findAddress(existing, addressId);
    if target is () {
        return ();
    }

    // An update can promote an address to default but never demote one: the
    // only way to stop being the default is for another address to take over.
    boolean makeDefault = req.isDefault || target.isDefault;
    Address[] result = cloneAddresses(existing, makeDefault);

    Address replacement = buildAddress(addressId, req);
    replacement.isDefault = makeDefault;
    foreach int i in 0 ..< result.length() {
        if result[i].addressId == addressId {
            result[i] = replacement;
        }
    }
    return result;
}

// Removing the default address promotes the first remaining one, so the
// "exactly one default" invariant survives a delete. Returns () for an unknown
// addressId, same as updateAddress.
public isolated function removeAddress(Address[] existing, string addressId) returns Address[]? {
    if findAddress(existing, addressId) is () {
        return ();
    }

    Address[] remaining = [];
    foreach Address candidate in existing {
        if candidate.addressId != addressId {
            remaining.push(candidate.clone());
        }
    }

    if remaining.length() > 0 && defaultAddress(remaining) is () {
        remaining[0].isDefault = true;
    }
    return remaining;
}

// Copies the list (so callers never mutate the array they passed in),
// optionally clearing every isDefault flag before a new default is installed.
isolated function cloneAddresses(Address[] addresses, boolean clearDefaults) returns Address[] {
    Address[] copies = [];
    foreach Address existing in addresses {
        Address copy = existing.clone();
        if clearDefaults {
            copy.isDefault = false;
        }
        copies.push(copy);
    }
    return copies;
}
