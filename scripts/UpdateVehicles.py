import requests, json, os

# thanks arztools
url = "https://api.arztools.tech/tools/arizona/vehicles.json"
response = requests.get(url, timeout=30)
response.encoding = "utf-8"
data = response.json()

os.makedirs("SmartVEH", exist_ok=True)
with open("SmartVEH/Vehicles.json", "w", encoding="cp1251") as f:
    json.dump(data, f, ensure_ascii=False, indent=4)

print("SmartVEH/Vehicles.json updated:", len(data), "models")
