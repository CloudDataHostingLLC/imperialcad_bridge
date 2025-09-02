-- Fired when a player purchases a vehicle in JG-Dealerships
RegisterNetEvent("jg-dealerships:client:purchase-vehicle:config", function(vehicle, plate, purchaseType, amount, paymentMethod, financed)
    local modelHash = GetEntityModel(vehicle)
    local modelCode = GetDisplayNameFromVehicleModel(modelHash) or "UNK"
    local label = GetLabelText(modelCode); if label == "NULL" then label = modelCode end

    local colorPrimary = select(1, GetVehicleColours(vehicle))

    TriggerServerEvent("imperialcad:registerVehicle", {
        plate = plate,
        model = label,
        make  = "UNKNOWN",
        color = tostring(colorPrimary),
        year  = "2015",
        vin   = ("VIN-%s-%s"):format(modelCode, plate),
        financed = financed == true,
        amount = amount,
        paymentMethod = paymentMethod,
        purchaseType = purchaseType
    })
end)
