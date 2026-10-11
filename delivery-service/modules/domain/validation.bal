// Returns a message describing the first missing field, or () when the request is valid.
public isolated function validateDriverRegistration(RegisterDriverRequest req) returns string? {
    if req.name.trim() == "" {
        return "name is required";
    }
    if req.phoneNumber.trim() == "" {
        return "phoneNumber is required";
    }
    if req.plateNumber.trim() == "" {
        return "plateNumber is required";
    }
    if req.vehicleType.trim() == "" {
        return "vehicleType is required";
    }
    return ();
}
