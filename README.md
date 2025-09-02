# ImperialCAD Bridge for JG-Dealership

This resource automatically registers purchased vehicles in **ImperialCAD** when a player buys a car through **JG-Dealership**.  

---

## ✅ Features

- Vehicles are **auto-registered in CAD** when purchased.
- Registered owner is set using the player’s **numeric SSN** from CAD.
- **VINs auto-generate** with `EKY` prefix and a valid check digit (no punctuation, strictly alphanumeric).
- Plates are sent with one space preserved (e.g. `123 ABC`).
- **Make/Model cleanup**:  
  - Strips out bad/unknown values.  
  - Removes agency suffixes (e.g. “Morgan SO”, “Police”).  
  - Keeps `(Marked)` / `(Unmarked)` suffixes when present.
- Insurance is automatically created with:
  - `insuranceStatus`: Active  
  - `insurancePolicyNum`: `POL-<PLATE>`  
- Title issue date is automatically generated.

---

## ⚠️ Known Limitation: Expiration Date

ImperialCAD’s DMV **Plate Return screen does not display any of the expiration fields we can send via API** (`regExpDate`, `expirationDate`, `titleExpDate`, etc.).

👉 Because of this, **Expiration Date will always appear blank** after auto-registration.  

Players (or admins) must **manually set the expiration date** inside CAD after the vehicle is registered.

---

## Player Instructions

1. Buy your vehicle through the dealership as normal.  
2. Open **ImperialCAD** → **Vehicles** → locate your new vehicle.  
3. Edit the record and set the **Expiration Date** manually.  
   - Default rule (our server): **1 year from purchase date**.  
   - Example: Purchased on `2025-09-01` → Expiration = `2026-09-01`.

---

## Configuration

- **Registration Length**: Change in `server.lua`  
  ```lua
  local REG_EXPIRES_IN_MONTHS = 12
  ```
- VIN prefix is hard-coded to `EKY`.
- Registration state is hard-coded to `KY`.

---

## Troubleshooting

- **Car not showing in CAD?**  
  - Check that `ImperialCAD` resource is running before `imperialcad_bridge`.  
  - Verify `imperial_community_id` and `imperialAPI` are set correctly in `server.cfg`.

- **Expiration Date still blank?**  
  - This is expected. CAD currently does not read the API fields we provide for expiration.

---

## Example Payload

For reference, here’s what gets sent on registration:

```json
{
  "vehicleData": {
    "plate": "123 ABC",
    "vin": "EKYABC123XYZ0000",
    "Make": "Ford",
    "model": "Explorer (Marked)",
    "year": 2015,
    "color": "Black",
    "regState": "KY",
    "regStatus": "Valid",
    "regExpDate": "2026-09-01",
    "expirationDate": "2026-09-01",
    "titleExpDate": "2026-09-01",
    "stolen": false
  },
  "vehicleInsurance": {
    "insuranceStatus": "Active",
    "insurancePolicyNum": "POL-123ABC",
    "hasInsurance": true
  },
  "vehicleOwner": {
    "ownerSSN": "878844104"
  }
}
```

---

## Credits

- Integration by [imperialcad_bridge]  
- VIN generator & Make/Model sanitizer written for this community setup.  
