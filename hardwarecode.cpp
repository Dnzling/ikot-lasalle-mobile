#include <Arduino.h>
#include <Wire.h>
#include <LittleFS.h>
#include <SoftwareSerial.h>
#include <ArduinoJson.h>
#include <time.h>
#include <sys/time.h>
#include <memory>
#include <new>
#include <bearssl/bearssl.h>


// Arduino IDE generates .ino function prototypes before the definitions below.
// Forward-declare these types so those generated prototypes can compile.
enum class CloudStatus : uint8_t;
struct GpsCacheRecord;

// =====================================================
// SIM808 GPRS relay configuration
// =====================================================
// Set RELAY_HOST to the public relay host, and use the same private 64-byte
// hex key as the server. Never commit the real key.
const char* SIM_APN = "internet";  // Smart
// The SIM808 uses plain HTTP through the ngrok tunnel.
const char* RELAY_HOST = "corset-coveting-thigh.ngrok-free.dev";
const uint16_t RELAY_PORT = 80;
const bool RELAY_USE_TLS = false;
const char* RELAY_KEY_HEX = "92b483d06e3c9fab06730dc0c514048b3f82b32adeb9a6a6dd82e9475ff9bdf2d75ceff710f0f0b59b11ac569273e8440a5386aa057b65d5af667ffe2e45a760";
// Copy the document ID (not the vehicle name) from Firestore > vehicles.
const char* VEHICLE_DOCUMENT_ID = "MTNdGikNTX1OybDv24Kn";
const char* VEHICLE_TYPE = "E-Jeep";




// =====================================================
// CONNECTIONS
// =====================================================
// LCD:
// SDA -> NodeMCU D2 / GPIO4
// SCL -> NodeMCU D1 / GPIO5
//
// SIM808:
// SIM808 TXD -> NodeMCU D6 / GPIO12
// SIM808 RXD -> NodeMCU D7 / GPIO13
// SIM808 GND -> NodeMCU GND




#define SIM808_RX D6
#define SIM808_TX D7




SoftwareSerial sim808(SIM808_RX, SIM808_TX);




// =====================================================
// LIBRARY-FREE I2C LCD
// =====================================================
#define LCD_ADDRESS 0x27
#define LCD_COLUMNS 20
#define LCD_ROWS 4




class SimpleI2CLCD {
private:
  uint8_t address;
  uint8_t backlight = 0x08;




  void expanderWrite(uint8_t data) {
    Wire.beginTransmission(address);
    Wire.write(data | backlight);
    Wire.endTransmission();
  }




  void pulseEnable(uint8_t data) {
    expanderWrite(data | 0x04);
    delayMicroseconds(1);




    expanderWrite(data & ~0x04);
    delayMicroseconds(50);
  }




  void write4Bits(uint8_t data) {
    expanderWrite(data);
    pulseEnable(data);
  }




  void send(uint8_t value, uint8_t mode) {
    uint8_t highNibble = value & 0xF0;
    uint8_t lowNibble = (value << 4) & 0xF0;




    write4Bits(highNibble | mode);
    write4Bits(lowNibble | mode);
  }




public:
  SimpleI2CLCD(uint8_t lcdAddress) {
    address = lcdAddress;
  }




  void command(uint8_t value) {
    send(value, 0x00);
  }




  void writeCharacter(uint8_t value) {
    send(value, 0x01);
  }




  void begin() {
    delay(50);




    expanderWrite(0x00);
    delay(1000);




    write4Bits(0x30);
    delayMicroseconds(4500);




    write4Bits(0x30);
    delayMicroseconds(4500);




    write4Bits(0x30);
    delayMicroseconds(150);




    write4Bits(0x20);




    command(0x28);
    command(0x08);
    clear();
    command(0x06);
    command(0x0C);
  }




  void clear() {
    command(0x01);
    delay(2);
  }




  void setCursor(uint8_t column, uint8_t row) {
    const uint8_t rowOffsets[] = {
      0x00, 0x40, 0x14, 0x54
    };




    if (row >= LCD_ROWS) {
      row = LCD_ROWS - 1;
    }




    command(0x80 | (column + rowOffsets[row]));
  }




  void print(const String& text) {
    for (unsigned int i = 0; i < text.length(); i++) {
      writeCharacter(text[i]);
    }
  }
};




SimpleI2CLCD lcd(LCD_ADDRESS);




// =====================================================
// JEEPNEY INFORMATION
// =====================================================
int onboardCount = 0;
int expectedOffboardingCount = 0;
String dbVehicleType = "--";
String dbVehicleStatus = "";
String dbLocationLabel = "";
bool vehicleDataLoaded = false;


extern double gpsLatitude;
extern double gpsLongitude;
extern double gpsSpeedKmh;
extern bool gpsHasFix;
extern bool gpsCoordinatesAvailable;




struct RouteStop {
  String id;
  String name;
  double latitude;
  double longitude;
  double radius;
};




RouteStop routeStops[30];
int routeStopCount = 0;
int currentStopIndex = -1;
bool routeMovingTowardLastStop = true;
void saveRouteDirection() {
  File file = LittleFS.open("/route_direction.state", "w");
  if (file) { file.write(routeMovingTowardLastStop ? '1' : '0'); file.close(); }
}
void loadRouteDirection() {
  File file = LittleFS.open("/route_direction.state", "r");
  if (file) { routeMovingTowardLastStop = file.read() == '1'; file.close(); }
}
bool routeOnCampus = false;
String latestGpsSpeedText = "SPEED: --";
String latestGpsEtaText = "ETA: --";


struct FuelingGate {
  double latitude;
  double longitude;
  double radius;
};

FuelingGate fuelingEntrance = {};
FuelingGate fuelingExit = {};
bool fuelingLocationsLoaded = false;
bool fuelingTripActive = false;


double distanceMeters(double latitude1, double longitude1,
                      double latitude2, double longitude2);




bool isFuelingTripActive() {
  return String(VEHICLE_TYPE) == "Jeep" && fuelingTripActive;
}

void loadFuelingTripState() {
  File file = LittleFS.open("/fueling.state", "r");
  if (!file) return;
  fuelingTripActive = file.read() == '1';
  file.close();
}

void updateFuelingTripState() {
  if (String(VEHICLE_TYPE) == "E-Jeep") return;
  if (!gpsHasFix || !fuelingLocationsLoaded) return;
  // Entrance wins if the configured radii overlap.
  const bool atEntrance = distanceMeters(gpsLatitude, gpsLongitude,
      fuelingEntrance.latitude, fuelingEntrance.longitude) <= fuelingEntrance.radius;
  const bool atExit = distanceMeters(gpsLatitude, gpsLongitude,
      fuelingExit.latitude, fuelingExit.longitude) <= fuelingExit.radius;
  const bool nextState = atEntrance ? false : atExit ? true : fuelingTripActive;
  if (nextState == fuelingTripActive) return;
  fuelingTripActive = nextState;
  File file = LittleFS.open("/fueling.state", "w");
  if (file) {
    file.write(fuelingTripActive ? '1' : '0');
    file.close();
  }
  Serial.println(fuelingTripActive ? "Fueling trip started at exit gate" :
      "Fueling trip ended at entrance gate");
}




String getRouteStopName(int index) {
  if (index < 0 || index >= routeStopCount) return "--";
  return routeStops[index].name;
}




String getLocationDisplayText() {
  if (!gpsHasFix) {
    return gpsCoordinatesAvailable ? "LOC: LAST FIX" : "LOC: NO GPS";
  }


  if (isFuelingTripActive()) return "LOC: FUELING GAS";


  if (!routeOnCampus) {
    return "LOC: OUTSIDE";
  }


  return currentStopIndex >= 0
      ? String("LOC: ") + routeStops[currentStopIndex].name
      : "LOC: CAMPUS";
}




int getEtaTargetStopIndex() {
  if ((!gpsHasFix && !gpsCoordinatesAvailable) || routeStopCount == 0) {
    return -1;
  }


  int nearestIndex = -1;
  double nearestDistance = 1e9;


  for (int i = 0; i < routeStopCount; ++i) {
    const double distance = distanceMeters(
        gpsLatitude, gpsLongitude,
        routeStops[i].latitude,
        routeStops[i].longitude);


    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearestIndex = i;
    }
  }


  if (nearestIndex < 0) return -1;

  if (currentStopIndex == nearestIndex && routeStopCount > 1) {
    const int next = nearestIndex + (routeMovingTowardLastStop ? 1 : -1);
    if (next >= 0 && next < routeStopCount) return next;
  }


  int gate1Index = -1;
  int gate3Index = -1;
  for (int i = 0; i < routeStopCount; ++i) {
    if (routeStops[i].id == "gate_1" || routeStops[i].name == "Gate 1") {
      gate1Index = i;
    }
    if (routeStops[i].id == "gate_3" || routeStops[i].name == "Gate 3") {
      gate3Index = i;
    }
  }


  if (!routeOnCampus && gate1Index >= 0 && gate3Index >= 0) {
    const double gate1Distance = distanceMeters(
        gpsLatitude, gpsLongitude,
        routeStops[gate1Index].latitude,
        routeStops[gate1Index].longitude);
    const double gate3Distance = distanceMeters(
        gpsLatitude, gpsLongitude,
        routeStops[gate3Index].latitude,
        routeStops[gate3Index].longitude);
    return gate1Distance <= gate3Distance ? gate1Index : gate3Index;
  }


  // Follow every stop in order and reverse at each gate endpoint.
  const int step = routeMovingTowardLastStop ? 1 : -1;
  const int targetIndex = nearestIndex + step;
  if (targetIndex < 0 || targetIndex >= routeStopCount) return nearestIndex;
  return targetIndex;
}




String getEstimatedArrivalText() {
  if ((!gpsHasFix && !gpsCoordinatesAvailable) || routeStopCount == 0) {
    return "ETA: --";
  }


  const int targetIndex = getEtaTargetStopIndex();
  if (targetIndex < 0) {
    return "ETA: --";
  }


  const RouteStop& target = routeStops[targetIndex];
  const double distanceMetersToTarget = distanceMeters(
      gpsLatitude, gpsLongitude,
      target.latitude,
      target.longitude);


  double estimatedSpeedKmh = gpsSpeedKmh > 0.0 ? gpsSpeedKmh : 8.0;
  if (estimatedSpeedKmh < 1.0) estimatedSpeedKmh = 1.0;


  const double etaSeconds =
      (distanceMetersToTarget / 1000.0) / estimatedSpeedKmh * 3600.0;
  int etaTotalSeconds = (int)round(etaSeconds);
  if (etaTotalSeconds < 1) etaTotalSeconds = 1;


  String targetName = target.name;
  if (target.id == "gate_1") targetName = "Gate 1";
  else if (target.id == "polca_parking") targetName = "Polca";
  else if (target.id == "cbaa") targetName = "CBAA";
  else if (target.id == "batibot") targetName = "Batibot";
  else if (target.id == "shs_bldg") targetName = "SHS Bldg";
  else if (target.id == "uls") targetName = "ULS";
  else if (target.id == "gate_3") targetName = "Gate 3";
  if (targetName.length() > 8) targetName = targetName.substring(0, 8);


  String etaDuration;
  if (etaTotalSeconds < 60) {
    etaDuration = String(etaTotalSeconds) + " sec";
  } else {
    const int etaTotalMinutes = (int)round(etaTotalSeconds / 60.0);
    etaDuration = String(etaTotalMinutes) + " min";
  }


  return "ETA " + targetName + " " + etaDuration;
}




void updateGpsDisplaySnapshot() {
  const bool haveCoordinates = gpsHasFix || gpsCoordinatesAvailable;
  latestGpsSpeedText = haveCoordinates
      ? String("SPEED: ") + String(gpsSpeedKmh, 2) + " km/h"
      : "SPEED: --";
  latestGpsEtaText = getEstimatedArrivalText();
}




String vehicleStatus = "BREAK";
enum class CloudStatus : uint8_t { connecting, uploadFailed, connected };
CloudStatus cloudStatus = CloudStatus::connecting;




// =====================================================
// GPS INFORMATION
// =====================================================
double gpsLatitude = 0.0;
double gpsLongitude = 0.0;
double gpsSpeedKmh = 0.0;




bool gpsHasFix = false;
bool gpsCoordinatesAvailable = false;
bool sim808Available = false;
bool cellularDataReady = false;




// Keep the last valid fix in LittleFS so a reset does not clear the display.
struct GpsCacheRecord {
  uint32_t magic;
  double latitude;
  double longitude;
  double speedKmh;
  uint32_t checksum;
};
const uint32_t GPS_CACHE_MAGIC = 0x47505331;
const char* GPS_CACHE_PATH = "/lastgps.bin";
unsigned long lastGpsCacheSave = 0;
double lastCachedLatitude = 999.0;
double lastCachedLongitude = 999.0;




// =====================================================
// STATUS CONDITIONS
// =====================================================
const double MOVEMENT_SPEED_KMH = 1.5;
const unsigned long BREAK_DELAY = 30000;




unsigned long stoppedSince = 0;




// =====================================================
// TIMING
// =====================================================
const unsigned long GPS_REQUEST_INTERVAL = 1000;
const unsigned long VEHICLE_SYNC_INTERVAL = 10000;
const unsigned long STOP_VEHICLE_SYNC_INTERVAL = 5000;
const unsigned long ROUTE_SYNC_INTERVAL = 300000;
const unsigned long ROUTE_RETRY_INTERVAL = 30000;
const unsigned long FUELING_SYNC_INTERVAL = 300000;
const unsigned long FUELING_RETRY_INTERVAL = 30000;
// Match the working Jeep's cadence to avoid saturating the SIM808 GPRS bearer.
const unsigned long GPS_UPLOAD_INTERVAL = 10000;
const unsigned long GPS_RESTART_DELAY = 2000;
const unsigned long SIM_RETRY_INTERVAL = 15000;




unsigned long lastGPSRequest = 0;
unsigned long lastVehicleSync = 0;
unsigned long lastRouteSync = 0;
unsigned long lastFuelingSync = 0;
unsigned long lastGPSUpload = 0;
unsigned long lastSuccessfulGpsUpload = 0;
unsigned long lastSIMRetry = 0;
unsigned long lastCellularRetry = 0;
bool relayHttpActionPending = false;
unsigned long relayHttpActionStarted = 0;


// =====================================================
// LCD FUNCTIONS
// =====================================================
String fitLCD(String text) {
  if (text.length() > LCD_COLUMNS) {
    text = text.substring(0, LCD_COLUMNS);
  }




  while (text.length() < LCD_COLUMNS) {
    text += " ";
  }




  return text;
}




void lcdLine(uint8_t row, String text) {
  lcd.setCursor(0, row);
  lcd.print(fitLCD(text));
}




void displayWelcomeScreen() {
  lcd.clear();
  lcdLine(0, "WELCOME TO IKOT");
  lcdLine(1, "LA SALLE");
  lcdLine(2, "TYPE: " + String(VEHICLE_TYPE));
  lcdLine(3, "");
  delay(3000);
}




void displayJeepInformation() {
  const String type = dbVehicleType.length() && dbVehicleType != "--"
      ? dbVehicleType : String(VEHICLE_TYPE);
  const String status = dbVehicleStatus.length() ? dbVehicleStatus : vehicleStatus;
  lcdLine(0, "TYPE: " + type);
  lcdLine(1, "STATUS: " + status);
  lcdLine(2, vehicleDataLoaded ? "ONBOARD: " + String(onboardCount) : "ONBOARD: --");
  lcdLine(3, vehicleDataLoaded ? "EXPECTED OFF: " + String(expectedOffboardingCount) : "EXPECTED OFF: --");
}




const char* cloudStatusText() {
  switch (cloudStatus) {
    case CloudStatus::connected: return "CONNECTED";
    case CloudStatus::uploadFailed: return "PENDING";
    default: return "CONNECTING...";
  }
}




void displayGPSLocation() {
  const bool haveCoordinates = gpsHasFix || gpsCoordinatesAvailable;
  if (haveCoordinates) {
    lcdLine(0, "LAT: " + String(gpsLatitude, 6));
    lcdLine(1, "LON: " + String(gpsLongitude, 6));
  } else {
    lcdLine(0, "LAT: --");
    lcdLine(1, "LON: --");
  }
  lcdLine(2, latestGpsSpeedText);
  lcdLine(3, latestGpsEtaText);
}


void displayGPSSummary() {
  lcdLine(0, dbLocationLabel.length() ? dbLocationLabel : "LOC: --");
  lcdLine(1, dbVehicleStatus.length() ? "STATUS: " + dbVehicleStatus : "STATUS: --");
  lcdLine(2, latestGpsSpeedText);
  lcdLine(3, latestGpsEtaText);
}




void drawCurrentLCDPage();




void setCloudStatus(CloudStatus nextStatus) {
  if (cloudStatus == nextStatus) return;
  cloudStatus = nextStatus;
  drawCurrentLCDPage();
}




void drawCurrentLCDPage() {
  displayJeepInformation();
}




// =====================================================
// SIM808 COMMUNICATION
// =====================================================
void clearSIMBuffer() {
  while (sim808.available()) {
    sim808.read();
  }
}




String sendATCommand(
  const String& command,
  unsigned long timeout
) {
  clearSIMBuffer();




  Serial.print(">> ");
  Serial.println(command);




  sim808.println(command);




  String response = "";
  unsigned long startTime = millis();
  unsigned long lastCharacterTime = millis();




  while (millis() - startTime < timeout) {
    while (sim808.available()) {
      char character = sim808.read();




      response += character;
      lastCharacterTime = millis();
    }




    if (response.length() > 0 &&
        millis() - lastCharacterTime > 400) {
      break;
    }




    yield();
  }




  Serial.println("<<");




  if (response.length() > 0) {
    Serial.println(response);
  } else {
    Serial.println("[NO RESPONSE]");
  }




  return response;
}

bool connectCellularData() {
  if (!sim808Available) return false;
  if (sendATCommand("AT+CPIN?", 3000).indexOf("READY") < 0) {
    Serial.println("SIM card is not ready");
    return false;
  }
  const String registration = sendATCommand("AT+CREG?", 3000);
  if (registration.indexOf(",1") < 0 && registration.indexOf(",5") < 0) {
    Serial.println("SIM808 has not registered on a GSM network");
    return false;
  }
  if (sendATCommand("AT+CGATT?", 3000).indexOf("+CGATT: 1") < 0) {
    Serial.println("SIM808 is not attached to GPRS");
    return false;
  }
  if (sendATCommand("AT+SAPBR=3,1,\"Contype\",\"GPRS\"", 3000).indexOf("OK") < 0 ||
      sendATCommand(String("AT+SAPBR=3,1,\"APN\",\"") + SIM_APN + "\"", 3000).indexOf("OK") < 0) {
    Serial.println("SIM808 GPRS APN configuration failed");
    return false;
  }
  String bearer = sendATCommand("AT+SAPBR=2,1", 3000);
  if (bearer.indexOf("+SAPBR: 1,1") < 0) {
    if (sendATCommand("AT+SAPBR=1,1", 12000).indexOf("OK") < 0) {
      Serial.println("SIM808 could not open GPRS bearer");
      return false;
    }
    bearer = sendATCommand("AT+SAPBR=2,1", 3000);
  }
  cellularDataReady = bearer.indexOf("+SAPBR: 1,1") >= 0;
  Serial.println(cellularDataReady ? "SIM808 GPRS ready" : "SIM808 GPRS bearer unavailable");
  return cellularDataReady;
}

void maintainCellularData() {
  if (!sim808Available || cellularDataReady ||
      millis() - lastCellularRetry < 30000) return;
  lastCellularRetry = millis();
  connectCellularData();
}




bool testSIM808() {
  for (int attempt = 1; attempt <= 3; attempt++) {
    Serial.print("SIM808 test attempt ");
    Serial.println(attempt);




    String response = sendATCommand("AT", 3000);




    if (response.indexOf("OK") >= 0) {
      Serial.println("SIM808 is responding");




      sim808Available = true;
      return true;
    }




    delay(1000);
  }




  Serial.println("SIM808 is unavailable");




  sim808Available = false;
  cellularDataReady = false;
  gpsHasFix = false;




  return false;
}




void initializeSIM808() {
  if (!testSIM808()) {
    return;
  }




  // Disable command echo.
  sendATCommand("ATE0", 3000);

  // Report the modem's reason when an AT command fails.
  sendATCommand("AT+CMEE=2", 3000);




  // Disable SIM808 UART sleep.
  sendATCommand("AT+CSCLK=0", 3000);




  sim808Available = true;
  cellularDataReady = false;
  connectCellularData();
}




// =====================================================
// GPS POWER CONTROL
// =====================================================
bool startGPS() {
  if (!sim808Available) {
    return false;
  }




  Serial.println("Turning GPS ON...");




  String response =
    sendATCommand("AT+CGNSPWR=1", 2000);




  if (response.indexOf("OK") < 0) {
    Serial.println("GPS power command failed");




    gpsHasFix = false;




    return false;
  }




  delay(GPS_RESTART_DELAY);




  response = sendATCommand("AT+CGNSPWR?", 2000);




  if (response.indexOf("+CGNSPWR: 1") >= 0) {
    Serial.println("GPS confirmed ON");




    return true;
  }




  Serial.println("GPS still reports OFF");




  gpsHasFix = false;




  return false;
}




// =====================================================
// GPS RESPONSE PARSING
// =====================================================
String getCSVField(
  const String& data,
  int requestedField
) {
  int currentField = 0;
  int fieldStart = 0;




  for (int i = 0; i <= (int)data.length(); i++) {
    if (i == (int)data.length() || data[i] == ',') {
      if (currentField == requestedField) {
        return data.substring(fieldStart, i);
      }




      currentField++;
      fieldStart = i + 1;
    }
  }




  return "";
}




String extractCGNSINFLine(const String& response) {
  int startPosition = response.indexOf("+CGNSINF:");




  if (startPosition < 0) {
    return "";
  }




  int lineEnd = response.indexOf('\n', startPosition);




  if (lineEnd < 0) {
    lineEnd = response.length();
  }




  String gpsLine =
    response.substring(startPosition + 9, lineEnd);




  gpsLine.trim();




  return gpsLine;
}




double degreesToRadians(double degrees) {
  return degrees * PI / 180.0;
}




double distanceMeters(
  double latitude1,
  double longitude1,
  double latitude2,
  double longitude2
) {
  const double earthRadiusMeters = 6371000.0;
  const double latitudeDifference = degreesToRadians(latitude2 - latitude1);
  const double longitudeDifference = degreesToRadians(longitude2 - longitude1);
  const double a =
      sin(latitudeDifference / 2.0) * sin(latitudeDifference / 2.0) +
      cos(degreesToRadians(latitude1)) * cos(degreesToRadians(latitude2)) *
      sin(longitudeDifference / 2.0) * sin(longitudeDifference / 2.0);
  return earthRadiusMeters * 2.0 * atan2(sqrt(a), sqrt(1.0 - a));
}




uint32_t gpsCacheChecksum(const GpsCacheRecord& record) {
  const uint8_t* bytes = reinterpret_cast<const uint8_t*>(&record);
  uint32_t hash = 2166136261u;
  for (size_t i = 0; i < offsetof(GpsCacheRecord, checksum); ++i) {
    hash = (hash ^ bytes[i]) * 16777619u;
  }
  return hash;
}




void loadGpsCache() {
  File file = LittleFS.open(GPS_CACHE_PATH, "r");
  if (!file) return;
  if (file.size() != sizeof(GpsCacheRecord)) {
    file.close();
    return;
  }
  GpsCacheRecord record = {};
  const size_t bytesRead =
      file.read(reinterpret_cast<uint8_t*>(&record), sizeof(record));
  file.close();
  if (bytesRead != sizeof(record) || record.magic != GPS_CACHE_MAGIC ||
      record.checksum != gpsCacheChecksum(record) ||
      !isfinite(record.latitude) || !isfinite(record.longitude) ||
      record.latitude < -90 || record.latitude > 90 ||
      record.longitude < -180 || record.longitude > 180 ||
      (record.latitude == 0 && record.longitude == 0)) {
    Serial.println("Saved GPS cache is invalid; waiting for a fresh fix");
    return;
  }
  gpsLatitude = record.latitude;
  gpsLongitude = record.longitude;
  gpsSpeedKmh = record.speedKmh;
  gpsCoordinatesAvailable = true;
  lastCachedLatitude = record.latitude;
  lastCachedLongitude = record.longitude;
  Serial.printf("Restored saved GPS coordinates: %.6f, %.6f (display only until fresh fix)\n",
                gpsLatitude, gpsLongitude);
}




void saveGpsCacheIfNeeded() {
  if (!gpsHasFix) return;
  const bool movedEnough = lastCachedLatitude == 999.0 ||
      distanceMeters(gpsLatitude, gpsLongitude,
                     lastCachedLatitude, lastCachedLongitude) >= 25.0;
  const bool saveDue = millis() - lastGpsCacheSave >= 60000;
  if (!movedEnough && !saveDue) return;




  GpsCacheRecord record = {};
  record.magic = GPS_CACHE_MAGIC;
  record.latitude = gpsLatitude;
  record.longitude = gpsLongitude;
  record.speedKmh = gpsSpeedKmh;
  record.checksum = gpsCacheChecksum(record);




  File file = LittleFS.open("/lastgps.tmp", "w");
  if (!file) {
    Serial.println("Could not open GPS cache for writing");
    return;
  }
  const size_t written =
      file.write(reinterpret_cast<const uint8_t*>(&record), sizeof(record));
  file.flush();
  file.close();
  if (written != sizeof(record)) {
    LittleFS.remove("/lastgps.tmp");
    Serial.println("GPS cache write was incomplete");
    return;
  }
  LittleFS.remove(GPS_CACHE_PATH);
  if (LittleFS.rename("/lastgps.tmp", GPS_CACHE_PATH)) {
    lastGpsCacheSave = millis();
    lastCachedLatitude = gpsLatitude;
    lastCachedLongitude = gpsLongitude;
    Serial.println("Last known GPS coordinates saved to LittleFS");
  }
}




void updateRouteDirectionAtEndpoint() {
  if (!gpsHasFix || routeStopCount < 2) return;

  int endpointIndex = -1;
  double endpointDistance = 1e9;
  const int endpoints[] = {0, routeStopCount - 1};
  for (int index : endpoints) {
    const RouteStop& stop = routeStops[index];
    const double distance = distanceMeters(gpsLatitude, gpsLongitude,
        stop.latitude, stop.longitude);
    if (distance <= stop.radius && distance < endpointDistance) {
      endpointIndex = index;
      endpointDistance = distance;
    }
  }
  if (endpointIndex < 0) return;

  const bool towardLast = endpointIndex == 0;
  if (routeMovingTowardLastStop == towardLast) return;
  routeMovingTowardLastStop = towardLast;
  saveRouteDirection();
  lastGPSUpload = millis() - GPS_UPLOAD_INTERVAL;
}

void updateCurrentStop() {
  if (!gpsHasFix || routeStopCount == 0) return;


  if (isFuelingTripActive()) {
    routeOnCampus = false;
    currentStopIndex = -1;
    expectedOffboardingCount = 0;
    return;
  }

  // Check route endpoints before the current-stop hysteresis early return.
  // Otherwise a nearby previous stop can mask arrival at the terminal.
  updateRouteDirectionAtEndpoint();




  if (currentStopIndex >= 0) {
    const RouteStop& stop = routeStops[currentStopIndex];
    if (distanceMeters(gpsLatitude, gpsLongitude, stop.latitude,
                       stop.longitude) <= stop.radius + 15.0) {
      return;
    }
  }




  int nearest = -1;
  double nearestDistance = 1e9;
  for (int i = 0; i < routeStopCount; ++i) {
    const RouteStop& stop = routeStops[i];
    const double distance = distanceMeters(
        gpsLatitude, gpsLongitude, stop.latitude, stop.longitude);
    if (distance <= stop.radius && distance < nearestDistance) {
      nearest = i;
      nearestDistance = distance;
    }
  }




  if (nearest == currentStopIndex) return;
  currentStopIndex = nearest;
  if (nearest >= 0) {
    if (routeStopCount > 1 &&
        (nearest == 0 || nearest == routeStopCount - 1)) {
      const bool towardLast = nearest == 0;
      if (routeMovingTowardLastStop != towardLast) {
        routeMovingTowardLastStop = towardLast;
        saveRouteDirection();
        lastGPSUpload = millis() - GPS_UPLOAD_INTERVAL;
      }
    }
    if (routeStops[nearest].id == "gate_1" ||
        routeStops[nearest].name == "Gate 1") {
      routeOnCampus = !routeOnCampus;
    } else if (routeStops[nearest].id == "gate_3" ||
               routeStops[nearest].name == "Gate 3") {
      routeOnCampus = !routeOnCampus;
    } else {
      routeOnCampus = true;
    }
  }
  expectedOffboardingCount = 0;
  lastVehicleSync = 0;
  drawCurrentLCDPage();
}




// =====================================================
// JEEPNEY STATUS
// =====================================================
void updateJeepneyStatus() {
  if (!gpsHasFix) {
    stoppedSince = 0;
    return;
  }
  updateFuelingTripState();
  if (isFuelingTripActive()) {
    stoppedSince = 0;
    vehicleStatus = "FUELING GAS";
    return;
  }
  if (vehicleStatus == "FUELING GAS") vehicleStatus = "ACTIVE";
  if (gpsSpeedKmh > MOVEMENT_SPEED_KMH) {
    stoppedSince = 0;
    vehicleStatus = "ACTIVE";
    return;
  }
  if (stoppedSince == 0) stoppedSince = millis();
  if (millis() - stoppedSince >= BREAK_DELAY) {
    vehicleStatus = "BREAK";
  }
}




void syncClockFromGPS(const String& gpsData) {
  if (time(nullptr) > 1700000000) return;
  const String utcText = getCSVField(gpsData, 2);
  if (utcText.length() < 14) return;
  for (int i = 0; i < 14; ++i) {
    if (utcText[i] < '0' || utcText[i] > '9') return;
  }
  struct tm utc = {};
  utc.tm_year = utcText.substring(0, 4).toInt() - 1900;
  utc.tm_mon = utcText.substring(4, 6).toInt() - 1;
  utc.tm_mday = utcText.substring(6, 8).toInt();
  utc.tm_hour = utcText.substring(8, 10).toInt();
  utc.tm_min = utcText.substring(10, 12).toInt();
  utc.tm_sec = utcText.substring(12, 14).toInt();
  utc.tm_isdst = 0;
  if (utc.tm_year < 124 || utc.tm_mon < 0 || utc.tm_mon > 11 ||
      utc.tm_mday < 1 || utc.tm_mday > 31 || utc.tm_hour > 23 ||
      utc.tm_min > 59 || utc.tm_sec > 59) return;
  // The SIM808 timestamp is UTC; mktime must use the same timezone.
  setTZ("UTC0");
  const time_t gpsEpoch = mktime(&utc);
  if (gpsEpoch <= 1700000000) return;
  struct timeval gpsTime = {gpsEpoch, 0};
  if (settimeofday(&gpsTime, nullptr) == 0) {
    Serial.printf("ESP8266 clock synchronized from SIM808 GPS UTC: %s\n",
                  utcText.c_str());
  }
}




bool parseGPSResponse(const String& response) {
  String gpsData = extractCGNSINFLine(response);




  if (gpsData.length() == 0) {
    Serial.println("No +CGNSINF line found");




    gpsHasFix = false;




    return false;
  }




  Serial.println("Parsed GPS data:");
  Serial.println(gpsData);




  int runningStatus =
    getCSVField(gpsData, 0).toInt();




  int fixStatus =
    getCSVField(gpsData, 1).toInt();




  Serial.print("GPS running status: ");
  Serial.println(runningStatus);




  Serial.print("GPS fix status: ");
  Serial.println(fixStatus);




  // Report an unexpected OFF state without restarting the GPS receiver.
  if (runningStatus != 1) {
    Serial.println("GPS engine reported OFF");




    gpsHasFix = false;
    drawCurrentLCDPage();




    return false;
  }




  // GPS is running but has no satellite fix.
  if (fixStatus != 1) {
    gpsHasFix = false;




    Serial.println("GPS is ON, but has no fix");
    Serial.println("Place antenna outdoors facing upward");




    return false;
  }




  syncClockFromGPS(gpsData);




  String latitudeText =
    getCSVField(gpsData, 3);




  String longitudeText =
    getCSVField(gpsData, 4);




  String speedText =
    getCSVField(gpsData, 6);




  if (latitudeText.length() == 0 ||
      longitudeText.length() == 0) {
    gpsHasFix = false;




    return false;
  }




  gpsLatitude = latitudeText.toDouble();
  gpsLongitude = longitudeText.toDouble();
  gpsSpeedKmh = speedText.toDouble();




  if (!isfinite(gpsLatitude) || !isfinite(gpsLongitude) ||
      gpsLatitude < -90 || gpsLatitude > 90 ||
      gpsLongitude < -180 || gpsLongitude > 180 ||
      (gpsLatitude == 0 && gpsLongitude == 0)) {
    gpsHasFix = false;
    return false;
  }




  gpsHasFix = true;
  gpsCoordinatesAvailable = true;
  saveGpsCacheIfNeeded();




  Serial.print("Latitude: ");
  Serial.println(gpsLatitude, 6);




  Serial.print("Longitude: ");
  Serial.println(gpsLongitude, 6);




  Serial.print("Speed: ");
  Serial.print(gpsSpeedKmh, 2);
  Serial.println(" km/h");




  updateJeepneyStatus();




  return true;
}




// =====================================================
// FETCH GPS
// =====================================================
void fetchGPS() {
  if (!sim808Available) {
    gpsHasFix = false;
    return;
  }




  String response =
    sendATCommand("AT+CGNSINF", 2000);




  if (response.indexOf("+CGNSINF:") < 0) {
    Serial.println("No GPS response received");




    String testResponse =
      sendATCommand("AT", 3000);




    if (testResponse.indexOf("OK") < 0) {
      sim808Available = false;
      gpsHasFix = false;
    } else {
      sim808Available = true;
      gpsHasFix = false;
    }




    return;
  }




  parseGPSResponse(response);
}




// =====================================================
// SIM808 RECOVERY
// =====================================================
void retrySIM808() {
  if (sim808Available) {
    return;
  }




  if (millis() - lastSIMRetry <
      SIM_RETRY_INTERVAL) {
    return;
  }




  lastSIMRetry = millis();




  Serial.println("Retrying SIM808 connection...");




  initializeSIM808();




  if (sim808Available) {
    startGPS();
  }




  drawCurrentLCDPage();
}

// =====================================================
// ENCRYPTED SIM808 -> RELAY TRANSPORT
// =====================================================
int hexNibble(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

bool decodeHex(const String& value, uint8_t* output, size_t length) {
  if (value.length() != length * 2) return false;
  for (size_t i = 0; i < length; ++i) {
    const int high = hexNibble(value[i * 2]);
    const int low = hexNibble(value[i * 2 + 1]);
    if (high < 0 || low < 0) return false;
    output[i] = (high << 4) | low;
  }
  return true;
}

String encodeHex(const uint8_t* input, size_t length) {
  static const char digits[] = "0123456789abcdef";
  String output;
  if (!output.reserve(length * 2)) return "";
  for (size_t i = 0; i < length; ++i) {
    output += digits[input[i] >> 4];
    output += digits[input[i] & 15];
  }
  return output;
}

bool relayConfigured() {
  return String(RELAY_HOST) != "YOUR_RELAY_HOST" &&
         strlen(RELAY_KEY_HEX) == 128;
}

void relayMac(const uint8_t* key, const char* direction,
              const uint8_t* nonce, const uint8_t* data,
              size_t dataLength, uint8_t output[32]) {
  br_hmac_key_context keyContext;
  br_hmac_key_init(&keyContext, &br_sha256_vtable, key + 32, 32);
  br_hmac_context context;
  br_hmac_init(&context, &keyContext, 0);
  br_hmac_update(&context, direction, 3);
  br_hmac_update(&context, nonce, 12);
  br_hmac_update(&context, data, dataLength);
  br_hmac_out(&context, output);
}

bool sealRelayMessage(const String& plain, String& envelope,
                      String& requestNonce) {
  uint8_t key[64];
  if (!decodeHex(String(RELAY_KEY_HEX), key, sizeof(key))) return false;
  uint8_t nonce[12];
  ESP.random(nonce, sizeof(nonce));
  std::unique_ptr<uint8_t[]> data(new (std::nothrow) uint8_t[plain.length()]);
  if (!data) return false;
  memcpy(data.get(), plain.c_str(), plain.length());
  br_aes_ct_ctr_keys aes;
  br_aes_ct_ctr_init(&aes, key, 32);
  br_aes_ct_ctr_run(&aes, nonce, 0, data.get(), plain.length());
  uint8_t signature[32];
  relayMac(key, "req", nonce, data.get(), plain.length(), signature);
  requestNonce = encodeHex(nonce, sizeof(nonce));
  JsonDocument json;
  json["v"] = 1;
  json["nonce"] = requestNonce;
  json["data"] = encodeHex(data.get(), plain.length());
  json["mac"] = encodeHex(signature, sizeof(signature));
  envelope = "";
  serializeJson(json, envelope);
  return !envelope.isEmpty();
}

bool openRelayMessage(const String& envelope, const String& requestNonce,
                      JsonDocument& result) {
  JsonDocument outer;
  if (deserializeJson(outer, envelope)) return false;
  const String nonceHex = outer["nonce"].as<String>();
  const String dataHex = outer["data"].as<String>();
  const String macHex = outer["mac"].as<String>();
  if (outer["v"].as<int>() != 1 || dataHex.length() % 2 != 0 ||
      dataHex.length() > 12000) return false;
  uint8_t key[64], nonce[12], signature[32];
  if (!decodeHex(String(RELAY_KEY_HEX), key, sizeof(key)) ||
      !decodeHex(nonceHex, nonce, sizeof(nonce)) ||
      !decodeHex(macHex, signature, sizeof(signature))) return false;
  const size_t length = dataHex.length() / 2;
  std::unique_ptr<uint8_t[]> data(new (std::nothrow) uint8_t[length + 1]);
  if (!data || !decodeHex(dataHex, data.get(), length)) return false;
  uint8_t expected[32];
  relayMac(key, "res", nonce, data.get(), length, expected);
  uint8_t difference = 0;
  for (size_t i = 0; i < sizeof(expected); ++i) difference |= expected[i] ^ signature[i];
  if (difference != 0) return false;
  br_aes_ct_ctr_keys aes;
  br_aes_ct_ctr_init(&aes, key, 32);
  br_aes_ct_ctr_run(&aes, nonce, 0, data.get(), length);
  data[length] = 0;
  if (deserializeJson(result, reinterpret_cast<const char*>(data.get()))) return false;
  return result["requestNonce"].as<String>() == requestNonce &&
         result["ok"].as<bool>();
}

bool relayHttpPost(const String& payload, String& response) {
  bool reconnectBearerAfterFailure = false;
  String failureReason;
  if (relayHttpActionPending) {
    if (millis() - relayHttpActionStarted < 120000) return false;
    // An earlier request never reported completion. Give it time before cleanup.
    sendATCommand("AT+HTTPTERM", 3000);
    relayHttpActionPending = false;
  }
  if (!cellularDataReady && !connectCellularData()) return false;
  String initResponse = sendATCommand("AT+HTTPINIT", 3000);
  if (initResponse.indexOf("OK") < 0) {
    // The ESP8266 can restart while the SIM808 still has an HTTP session open.
    sendATCommand("AT+HTTPTERM", 3000);
    delay(200);
    initResponse = sendATCommand("AT+HTTPINIT", 3000);
    if (initResponse.indexOf("OK") < 0) {
      // The modem can retain a stale HTTP/bearer state after a failed request.
      // Reopen its GPRS bearer instead of repeating HTTPINIT indefinitely.
      Serial.println("SIM808 HTTP service stuck; reopening GPRS bearer");
      sendATCommand("AT+SAPBR=0,1", 12000);
      cellularDataReady = false;
      delay(500);
      if (!connectCellularData()) return false;
      initResponse = sendATCommand("AT+HTTPINIT", 3000);
      if (initResponse.indexOf("OK") < 0) {
        cellularDataReady = false;
        Serial.println("SIM808 HTTP service still unavailable after bearer recovery");
        return false;
      }
    }
  }
  bool okay = false;
  do {
    if (sendATCommand("AT+HTTPPARA=\"CID\",1", 3000).indexOf("OK") < 0) break;
    const String url = String("http://") + RELAY_HOST + ":" + RELAY_PORT + "/relay";
    if (sendATCommand(String("AT+HTTPPARA=\"URL\",\"") + url + "\"", 3000).indexOf("OK") < 0) break;
    if (sendATCommand("AT+HTTPPARA=\"CONTENT\",\"application/json\"", 3000).indexOf("OK") < 0) break;
    // Relay payload remains AES-encrypted and HMAC-authenticated end-to-end.
    if (sendATCommand(String("AT+HTTPSSL=") + (RELAY_USE_TLS ? "1" : "0"), 3000).indexOf("OK") < 0) {
      Serial.println("SIM808 could not set the relay transport TLS mode");
      break;
    }
    if (RELAY_USE_TLS && sendATCommand("AT+SSLOPT=0,1", 3000).indexOf("OK") < 0) {
      Serial.println("SIM808 firmware does not accept AT+SSLOPT=0,1");
      break;
    }
    if (sendATCommand(String("AT+HTTPDATA=") + payload.length() + ",10000", 3000).indexOf("DOWNLOAD") < 0) break;
    sim808.print(payload);
    String accepted;
    const unsigned long dataStarted = millis();
    while (millis() - dataStarted < 12000 && accepted.indexOf("OK") < 0) {
      while (sim808.available()) accepted += char(sim808.read());
      if (accepted.length() > 100) break;
      yield();
    }
    if (accepted.indexOf("OK") < 0) break;
    clearSIMBuffer();
    sim808.println("AT+HTTPACTION=1");
    relayHttpActionPending = true;
    relayHttpActionStarted = millis();
    String action;
    while (millis() - relayHttpActionStarted < 90000) {
      while (sim808.available()) action += char(sim808.read());
      const int marker = action.indexOf("+HTTPACTION:");
      if (marker >= 0 && action.indexOf('\n', marker) >= 0) break;
      if (action.length() > 300) break;
      yield();
    }
    const int actionMarker = action.indexOf("+HTTPACTION:");
    if (actionMarker < 0 || action.indexOf('\n', actionMarker) < 0) {
      Serial.println("SIM808 HTTP action still pending; leaving session open");
      return false;
    }
    relayHttpActionPending = false;
    Serial.println("SIM808 HTTP action result: " + action);
    const int firstComma = action.indexOf(',', actionMarker);
    const int secondComma = firstComma < 0 ? -1 : action.indexOf(',', firstComma + 1);
    int httpStatus = -1;
    if (firstComma >= 0 && secondComma > firstComma) {
      httpStatus = action.substring(firstComma + 1, secondComma).toInt();
    }
    if (httpStatus != 200) {
      if (httpStatus == 601) {
        failureReason = "SIM808 network error 601: no HTTP connection was established";
        reconnectBearerAfterFailure = true;
      } else if (httpStatus >= 600) {
        failureReason = String("SIM808 transport error ") + httpStatus;
        reconnectBearerAfterFailure = true;
      } else if (httpStatus >= 0) {
        failureReason = String("Relay returned HTTP status ") + httpStatus;
      } else {
        failureReason = "Could not parse SIM808 HTTPACTION status";
      }
      Serial.println("Relay upload failed: " + failureReason);
      cellularDataReady = false;
      break;
    }
    const String raw = sendATCommand("AT+HTTPREAD", 30000);
    const int marker = raw.indexOf("+HTTPREAD:");
    const int bodyStart = marker < 0 ? -1 : raw.indexOf('\n', marker) + 1;
    const int bodyEnd = raw.lastIndexOf("\r\nOK");
    if (bodyStart <= 0 || bodyEnd <= bodyStart) break;
    response = raw.substring(bodyStart, bodyEnd);
    response.trim();
    okay = true;
  } while (false);
  sendATCommand("AT+HTTPTERM", 3000);
  if (reconnectBearerAfterFailure) {
    // A stale PDP context can leave the SIM808 registered with an IP but unable
    // to open a new TCP socket. Reopen it once, then let the normal upload
    // schedule retry instead of hammering the modem.
    Serial.println("Checking SIM808 link after relay transport failure");
    sendATCommand("AT+CSQ", 3000);
    sendATCommand("AT+CREG?", 3000);
    sendATCommand("AT+CGATT?", 3000);
    sendATCommand("AT+SAPBR=2,1", 3000);
    Serial.println("Reopening SIM808 GPRS bearer before next upload retry");
    sendATCommand("AT+SAPBR=0,1", 12000);
    cellularDataReady = false;
    delay(1000);
    if (!connectCellularData()) {
      Serial.println("SIM808 bearer recovery failed; will retry on the next scheduled upload");
    }
  }
  if (!okay && !failureReason.isEmpty()) {
    Serial.println("SIM808 relay failure detail: " + failureReason);
  }
  return okay;
}

bool relayRequest(JsonDocument& request, JsonDocument& response) {
  if (!relayConfigured()) {
    Serial.println("Relay host or key is not configured");
    return false;
  }
  if (time(nullptr) <= 1700000000) {
    Serial.println("Relay request waiting for GPS UTC time");
    return false;
  }
  request["deviceId"] = VEHICLE_DOCUMENT_ID;
  request["ts"] = static_cast<int64_t>(time(nullptr));
  String plain;
  serializeJson(request, plain);
  String envelope, nonce, reply;
  if (!sealRelayMessage(plain, envelope, nonce) ||
      !relayHttpPost(envelope, reply) ||
      !openRelayMessage(reply, nonce, response)) {
    Serial.println("Encrypted relay request failed");
    return false;
  }
  return true;
}




// =====================================================
// RELAY OPERATIONS
// =====================================================
void syncRouteStopsRelay() {
  JsonDocument request, response;
  request["op"] = "routes";
  if (!relayRequest(request, response)) return;
  const String previousStopId = currentStopIndex >= 0
      ? routeStops[currentStopIndex].id : "";
  int count = 0;
  for (JsonVariant item : response["routes"].as<JsonArray>()) {
    RouteStop& stop = routeStops[count];
    stop.id = item["id"].as<String>();
    stop.latitude = item["latitude"].as<double>();
    stop.longitude = item["longitude"].as<double>();
    stop.radius = item["radius"].as<double>();
    if (stop.radius <= 0) stop.radius = 40.0;
    stop.name = item["name"].as<String>();
    if (stop.name.isEmpty()) stop.name = stop.id;
    if (++count >= 30) break;
  }
  routeStopCount = count;
  currentStopIndex = -1;
  for (int i = 0; i < routeStopCount; ++i) {
    if (routeStops[i].id == previousStopId) {
      currentStopIndex = i;
      break;
    }
  }
  expectedOffboardingCount = 0;
  updateCurrentStop();
  updateGpsDisplaySnapshot();
  drawCurrentLCDPage();
}

void syncFuelingLocationsRelay() {
  JsonDocument request, response;
  request["op"] = "fueling";
  if (!relayRequest(request, response)) return;
  JsonVariant entrance = response["entrance"];
  JsonVariant exit = response["exit"];
  if (entrance.isNull() || exit.isNull()) return;
  FuelingGate nextEntrance = {entrance["latitude"].as<double>(),
      entrance["longitude"].as<double>(), entrance["radius"].as<double>()};
  FuelingGate nextExit = {exit["latitude"].as<double>(),
      exit["longitude"].as<double>(), exit["radius"].as<double>()};
  if (!isfinite(nextEntrance.latitude) || !isfinite(nextEntrance.longitude) ||
      !isfinite(nextExit.latitude) || !isfinite(nextExit.longitude) ||
      nextEntrance.radius <= 0 || nextExit.radius <= 0 ||
      (nextEntrance.latitude == 0 && nextEntrance.longitude == 0) ||
      (nextExit.latitude == 0 && nextExit.longitude == 0)) return;
  fuelingEntrance = nextEntrance;
  fuelingExit = nextExit;
  fuelingLocationsLoaded = true;
  updateJeepneyStatus();
  updateCurrentStop();
  Serial.println("Fueling entrance, exit, and radii loaded from Firebase settings");
}

void syncVehicleDataRelay() {
  JsonDocument request, response;
  request["op"] = "vehicle";
  if (!relayRequest(request, response)) return;
  dbVehicleType = response["type"].as<String>();
  if (dbVehicleType.isEmpty()) dbVehicleType = "--";
  dbVehicleStatus = response["status"].as<String>();
  dbVehicleStatus.toUpperCase();
  dbLocationLabel = response["locationLabel"].as<String>();
  const String serverDirection = response["routeDirection"].as<String>();
  if (serverDirection == "towardLastStop" ||
      serverDirection == "towardFirstStop") {
    const bool towardLast = serverDirection == "towardLastStop";
    if (routeMovingTowardLastStop != towardLast) {
      routeMovingTowardLastStop = towardLast;
      saveRouteDirection();
      lastGPSUpload = millis() - GPS_UPLOAD_INTERVAL;
    }
  }
  onboardCount = response["onboard"].as<int>();
  expectedOffboardingCount = 0;
  const int step = routeMovingTowardLastStop ? 1 : -1;
  const int candidate = currentStopIndex + step;
  const int nextStopIndex = currentStopIndex >= 0 &&
      candidate >= 0 && candidate < routeStopCount
      ? candidate : getEtaTargetStopIndex();
  if (nextStopIndex >= 0) {
    const String routeId = routeStops[nextStopIndex].id;
    JsonVariantConst expected = response["expected"][routeId.c_str()];
    expectedOffboardingCount = expected.is<int>()
        ? expected.as<int>() : expected.as<unsigned int>();
    Serial.printf("Vehicle DB sync: onboard=%d, nextStop=%s, expectedOff=%d\n",
        onboardCount, routeId.c_str(), expectedOffboardingCount);
  } else {
    Serial.printf("Vehicle DB sync: onboard=%d, no next stop selected\n",
        onboardCount);
  }
  vehicleDataLoaded = true;
  drawCurrentLCDPage();
}

void uploadVehicleLocationRelay() {
  if (!gpsHasFix) return;
  JsonDocument request, response;
  request["op"] = "gps";
  request["latitude"] = gpsLatitude;
  request["longitude"] = gpsLongitude;
  request["speedKmh"] = gpsSpeedKmh;
  request["type"] = VEHICLE_TYPE;
  if (routeStopCount > 1) request["routeDirection"] =
      routeMovingTowardLastStop ? "towardLastStop" : "towardFirstStop";
  String locationLabel = getLocationDisplayText();
  locationLabel.replace("\r", " ");
  locationLabel.replace("\n", " ");
  if (locationLabel.length() > 40) locationLabel = locationLabel.substring(0, 40);
  request["locationLabel"] = locationLabel;
  request["status"] = vehicleStatus == "FUELING GAS" ? "fueling gas" :
                      vehicleStatus == "BREAK" ? "break" : "active";
  if (!relayRequest(request, response)) {
    setCloudStatus(CloudStatus::uploadFailed);
    return;
  }
  lastSuccessfulGpsUpload = millis();
  setCloudStatus(CloudStatus::connected);
  Serial.println("Vehicle GPS uploaded through SIM808 relay");
}




// =====================================================
// SETUP
// =====================================================
void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("ESP8266 reset reason: " + ESP.getResetReason());




  Serial.println();
  Serial.println("SIM808 GPS Tracker Starting");






  // LCD I2C: SDA D2, SCL D1.
  Wire.begin(D2, D1);




  lcd.begin();
  lcd.clear();




  displayWelcomeScreen();
  displayJeepInformation();




  // SIM808 communicates at 9600 baud.
  sim808.begin(9600);
  delay(2000);




  if (!LittleFS.begin()) {
    Serial.println("LittleFS mount failed; GPS cache is unavailable");
  } else {
    loadGpsCache();
    loadFuelingTripState();
    loadRouteDirection();
  }








  updateGpsDisplaySnapshot();
  initializeSIM808();




  if (sim808Available) {
    drawCurrentLCDPage();




    startGPS();




    delay(2000);




    fetchGPS();
    updateCurrentStop();
    if (gpsHasFix) updateGpsDisplaySnapshot();
    uploadVehicleLocationRelay();
    lastGPSUpload = millis();
  }




  // GPS upload gets first use of the network and heap. Optional reads run later.




  lastGPSRequest = millis();
  drawCurrentLCDPage();
}




// =====================================================
// MAIN LOOP
// =====================================================
void loop() {
  maintainCellularData();
  if (cloudStatus == CloudStatus::connected &&
      millis() - lastSuccessfulGpsUpload > 30000) {
    setCloudStatus(CloudStatus::uploadFailed);
  }
  retrySIM808();
  if (sim808Available &&
      millis() - lastGPSRequest >=
      GPS_REQUEST_INTERVAL) {
    lastGPSRequest = millis();




    fetchGPS();
    updateCurrentStop();
    if (gpsHasFix) updateGpsDisplaySnapshot();
    drawCurrentLCDPage();
  }




  if (gpsHasFix && millis() - lastGPSUpload >= GPS_UPLOAD_INTERVAL) {
    lastGPSUpload = millis();
    uploadVehicleLocationRelay();
  }




  if (cloudStatus == CloudStatus::connected &&
      (lastRouteSync == 0 || millis() - lastRouteSync >=
          (routeStopCount > 0 ? ROUTE_SYNC_INTERVAL : ROUTE_RETRY_INTERVAL))) {
    lastRouteSync = millis();
    syncRouteStopsRelay();
  }

  if (String(VEHICLE_TYPE) == "Jeep" && cloudStatus == CloudStatus::connected &&
      (lastFuelingSync == 0 || millis() - lastFuelingSync >=
          (fuelingLocationsLoaded ? FUELING_SYNC_INTERVAL : FUELING_RETRY_INTERVAL))) {
    lastFuelingSync = millis();
    syncFuelingLocationsRelay();
  }




  if (cloudStatus == CloudStatus::connected &&
      millis() - lastVehicleSync >=
          (currentStopIndex >= 0
               ? STOP_VEHICLE_SYNC_INTERVAL
               : VEHICLE_SYNC_INTERVAL)) {
    lastVehicleSync = millis();
    syncVehicleDataRelay();
  }


  yield();
}
