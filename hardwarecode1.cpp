#include <Arduino.h>
#include <Wire.h>
#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClientSecureBearSSL.h>
#include <SoftwareSerial.h>
#include <ArduinoJson.h>
#include <time.h>

// =====================================================
// WIFI
// =====================================================
// Configure these locally before flashing. Do not commit real passwords.
const char* WIFI_SSID     = "Niger A25";
const char* WIFI_PASSWORD = "PepegaDevotion09165242783";

// Firebase Authentication > Users: create a dedicated email/password account
// for this physical Jeep tracker. Use the WEB API key from firebase_options.dart.
const char* FIREBASE_API_KEY = "AIzaSyC0YXQ83GCutpozyK2wi0B3vH8V2zKt5IQ";
// Both trackers may use the same dedicated Firebase Authentication account.
// VEHICLE_DOCUMENT_ID below determines which vehicle each board updates.
const char* FIREBASE_DEVICE_EMAIL = "jeeplasalle@email.com";
const char* FIREBASE_DEVICE_PASSWORD = "jeeplasalle1";
// Copy the document ID (not the vehicle name) from Firestore > vehicles.
const char* VEHICLE_DOCUMENT_ID = "fVzHxxqNmYGYKd5gxmqi";
const char* FIREBASE_PROJECT_ID = "ikot-lasalle-ccfab";

// Download the PEM for the CA that currently validates both Google API hosts
// from its official issuer, and paste it here before using this in production.
// Fail closed rather than sending Firebase credentials over unverified TLS.
const char* FIREBASE_ROOT_CA = R"EOF(-----BEGIN CERTIFICATE-----
MIIFVzCCAz+gAwIBAgINAgPlk28xsBNJiGuiFzANBgkqhkiG9w0BAQwFADBHMQsw
CQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2VzIExMQzEU
MBIGA1UEAxMLR1RTIFJvb3QgUjEwHhcNMTYwNjIyMDAwMDAwWhcNMzYwNjIyMDAw
MDAwWjBHMQswCQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZp
Y2VzIExMQzEUMBIGA1UEAxMLR1RTIFJvb3QgUjEwggIiMA0GCSqGSIb3DQEBAQUA
A4ICDwAwggIKAoICAQC2EQKLHuOhd5s73L+UPreVp0A8of2C+X0yBoJx9vaMf/vo
27xqLpeXo4xL+Sv2sfnOhB2x+cWX3u+58qPpvBKJXqeqUqv4IyfLpLGcY9vXmX7w
Cl7raKb0xlpHDU0QM+NOsROjyBhsS+z8CZDfnWQpJSMHobTSPS5g4M/SCYe7zUjw
TcLCeoiKu7rPWRnWr4+wB7CeMfGCwcDfLqZtbBkOtdh+JhpFAz2weaSUKK0Pfybl
qAj+lug8aJRT7oM6iCsVlgmy4HqMLnXWnOunVmSPlk9orj2XwoSPwLxAwAtcvfaH
szVsrBhQf4TgTM2S0yDpM7xSma8ytSmzJSq0SPly4cpk9+aCEI3oncKKiPo4Zor8
Y/kB+Xj9e1x3+naH+uzfsQ55lVe0vSbv1gHR6xYKu44LtcXFilWr06zqkUspzBmk
MiVOKvFlRNACzqrOSbTqn3yDsEB750Orp2yjj32JgfpMpf/VjsPOS+C12LOORc92
wO1AK/1TD7Cn1TsNsYqiA94xrcx36m97PtbfkSIS5r762DL8EGMUUXLeXdYWk70p
aDPvOmbsB4om3xPXV2V4J95eSRQAogB/mqghtqmxlbCluQ0WEdrHbEg8QOB+DVrN
VjzRlwW5y0vtOUucxD/SVRNuJLDWcfr0wbrM7Rv1/oFB2ACYPTrIrnqYNxgFlQID
AQABo0IwQDAOBgNVHQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4E
FgQU5K8rJnEaK0gnhS9SZizv8IkTcT4wDQYJKoZIhvcNAQEMBQADggIBAJ+qQibb
C5u+/x6Wki4+omVKapi6Ist9wTrYggoGxval3sBOh2Z5ofmmWJyq+bXmYOfg6LEe
QkEzCzc9zolwFcq1JKjPa7XSQCGYzyI0zzvFIoTgxQ6KfF2I5DUkzps+GlQebtuy
h6f88/qBVRRiClmpIgUxPoLW7ttXNLwzldMXG+gnoot7TiYaelpkttGsN/H9oPM4
7HLwEXWdyzRSjeZ2axfG34arJ45JK3VmgRAhpuo+9K4l/3wV3s6MJT/KYnAK9y8J
ZgfIPxz88NtFMN9iiMG1D53Dn0reWVlHxYciNuaCp+0KueIHoI17eko8cdLiA6Ef
MgfdG+RCzgwARWGAtQsgWSl4vflVy2PFPEz0tv/bal8xa5meLMFrUKTX5hgUvYU/
Z6tGn6D/Qqc6f1zLXbBwHSs09dR2CQzreExZBfMzQsNhFRAbd03OIozUhfJFfbdT
6u9AWpQKXCBfTkBdYiJ23//OYb2MI3jSNwLgjt7RETeJ9r/tSQdirpLsQBqvFAnZ
0E6yove+7u7Y/9waLd64NnHi/Hm3lCXRSHNboTXns5lndcEZOitHTtNCjv0xyBZm
2tIMPNuzjsmhDYAPexZ3FL//2wmUspO8IFgV6dtxQ/PeEMMA3KgqlbbC1j+Qa3bb
bP6MvPJwNQzcmRk13NfIRmPVNnGuV/u3gm3c
-----END CERTIFICATE-----)EOF";

String firebaseIdToken;
unsigned long firebaseTokenIssuedAt = 0;
unsigned long firebaseTokenLifetimeMs = 0;
unsigned long lastFirebaseAuthAttempt = 0;
const unsigned long FIREBASE_AUTH_RETRY_MS = 30000;

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
const String VEHICLE_TYPE = "E-Jeep";

int onboardCount = 0;
int outboardCount = 0;
int expectedOffCount = 0;
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
bool stopTransitionPending = false;
unsigned long stopEnteredAt = 0;

String jeepneyStatus = "STARTING";
String vehicleStatus = "IDLE";

// =====================================================
// GPS INFORMATION
// =====================================================
double gpsLatitude = 0.0;
double gpsLongitude = 0.0;
double gpsSpeedKmh = 0.0;

bool gpsHasFix = false;
bool sim808Available = false;
bool fuelingMode = false;

// =====================================================
// STATUS CONDITIONS
// =====================================================
const double MOVEMENT_SPEED_KMH = 1.5;
const unsigned long BREAK_DELAY = 30000;

// Fueling entry location
const double FUEL_ENTRY_LAT = 14.322621555762716;
const double FUEL_ENTRY_LON = 120.96376350989355;

// Fueling exit location
const double FUEL_EXIT_LAT = 14.32056586315423;
const double FUEL_EXIT_LON = 120.96333703866406;

const double FUEL_RADIUS_METERS = 40.0;

unsigned long stoppedSince = 0;

// =====================================================
// TIMING
// =====================================================
const unsigned long GPS_REQUEST_INTERVAL = 1000;
const unsigned long VEHICLE_SYNC_INTERVAL = 10000;
const unsigned long STOP_VEHICLE_SYNC_INTERVAL = 5000;
const unsigned long ROUTE_SYNC_INTERVAL = 300000;
const unsigned long GPS_UPLOAD_INTERVAL = 2000;
const unsigned long GPS_WATCHDOG_INTERVAL = 15000;
const unsigned long BATTERY_CHECK_INTERVAL = 30000;
const unsigned long GPS_RESTART_DELAY = 2000;
const unsigned long LCD_PAGE_INTERVAL = 3000;
const unsigned long WIFI_RETRY_INTERVAL = 30000;
const unsigned long SIM_RETRY_INTERVAL = 15000;

unsigned long lastGPSRequest = 0;
unsigned long lastVehicleSync = 0;
unsigned long lastRouteSync = 0;
unsigned long lastGPSUpload = 0;
unsigned long lastGPSWatchdog = 0;
unsigned long lastBatteryCheck = 0;
unsigned long lastLCDPageSwitch = 0;
unsigned long lastWiFiRetry = 0;
unsigned long lastSIMRetry = 0;

uint8_t lcdPage = 0;

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

void displayJeepInformation() {
  lcdLine(0, currentStopIndex >= 0 ? "STOP: " + routeStops[currentStopIndex].name : "TYPE: " + VEHICLE_TYPE);
  lcdLine(1, "STATUS: " + vehicleStatus);
  lcdLine(2, "ONBOARD: " + String(onboardCount));
  lcdLine(3, currentStopIndex >= 0 ? "EXPECTED OFF: " + String(expectedOffCount) : "OUTBOARD: " + String(outboardCount));
}

void displayGPSLocation() {
  if (gpsHasFix) {
    lcdLine(0, "LAT: " + String(gpsLatitude, 6));
    lcdLine(1, "LON: " + String(gpsLongitude, 6));
    lcdLine(2, "SPEED: " + String(gpsSpeedKmh, 1));
    lcdLine(3, "STATUS: " + vehicleStatus);
  } else {
    lcdLine(0, "LAT: WAITING");
    lcdLine(1, "LON: WAITING");
    lcdLine(2, "GPS: NO FIX");
    lcdLine(3, "STATUS: " + vehicleStatus);
  }
}

void drawCurrentLCDPage() {
  if (lcdPage == 0) {
    displayJeepInformation();
  } else {
    displayGPSLocation();
  }
}

void updateLCDPages() {
  if (currentStopIndex >= 0 || (stopEnteredAt != 0 && millis() - stopEnteredAt < 10000)) {
    if (lcdPage != 0) {
      lcdPage = 0;
      drawCurrentLCDPage();
    }
    lastLCDPageSwitch = millis();
    return;
  }
  if (millis() - lastLCDPageSwitch >= LCD_PAGE_INTERVAL) {
    lastLCDPageSwitch = millis();

    lcdPage++;

    if (lcdPage > 1) {
      lcdPage = 0;
    }

    drawCurrentLCDPage();
  }
}

// =====================================================
// WIFI
// =====================================================
void connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) {
    return;
  }

  Serial.println();
  Serial.print("Connecting to WiFi: ");
  Serial.println(WIFI_SSID);

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  unsigned long started = millis();

  while (WiFi.status() != WL_CONNECTED &&
         millis() - started < 15000) {
    delay(500);
    yield();
    Serial.print(".");
  }

  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("WiFi connected");

    Serial.print("IP address: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("WiFi connection failed");
  }
}

void maintainWiFi() {
  if (WiFi.status() == WL_CONNECTED) {
    return;
  }

  if (millis() - lastWiFiRetry >= WIFI_RETRY_INTERVAL) {
    lastWiFiRetry = millis();
    connectWiFi();
  }
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

void logSIM808Battery() {
  if (!sim808Available) {
    return;
  }

  if (lastBatteryCheck != 0 &&
      millis() - lastBatteryCheck < BATTERY_CHECK_INTERVAL) {
    return;
  }

  lastBatteryCheck = millis();

  Serial.println("Checking SIM808 battery...");

  String response = sendATCommand("AT+CBC", 3000);

  if (response.indexOf("+CBC:") < 0) {
    Serial.println("Unable to read SIM808 battery level");
  }
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
  gpsHasFix = false;
  jeepneyStatus = "SIM ERROR";

  return false;
}

void initializeSIM808() {
  if (!testSIM808()) {
    return;
  }

  // Disable command echo.
  sendATCommand("ATE0", 3000);

  // Disable SIM808 UART sleep.
  sendATCommand("AT+CSCLK=0", 3000);

  sim808Available = true;
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
    sendATCommand("AT+CGNSPWR=1", 5000);

  if (response.indexOf("OK") < 0) {
    Serial.println("GPS power command failed");

    gpsHasFix = false;
    jeepneyStatus = "GPS ERROR";

    return false;
  }

  delay(GPS_RESTART_DELAY);

  response = sendATCommand("AT+CGNSPWR?", 5000);

  if (response.indexOf("+CGNSPWR: 1") >= 0) {
    Serial.println("GPS confirmed ON");

    if (!gpsHasFix) {
      jeepneyStatus = "NO FIX";
    }

    return true;
  }

  Serial.println("GPS still reports OFF");

  gpsHasFix = false;
  jeepneyStatus = "GPS OFF";

  return false;
}

void keepGPSOn() {
  if (millis() - lastGPSWatchdog <
      GPS_WATCHDOG_INTERVAL) {
    return;
  }

  lastGPSWatchdog = millis();

  Serial.println();
  Serial.println("Running GPS watchdog...");

  // Check whether the SIM808 itself is alive.
  String response = sendATCommand("AT", 3000);

  if (response.indexOf("OK") < 0) {
    Serial.println("SIM808 stopped responding");

    sim808Available = false;
    gpsHasFix = false;
    jeepneyStatus = "SIM ERROR";

    drawCurrentLCDPage();
    return;
  }

  sim808Available = true;

  // Prevent serial sleep.
  sendATCommand("AT+CSCLK=0", 3000);

  // Reassert ON without ever cycling the GPS engine off.
  response = sendATCommand("AT+CGNSPWR=1", 3000);

  if (response.indexOf("OK") >= 0) {
    Serial.println("GPS watchdog: continuous ON requested");
  } else {
    Serial.println("GPS watchdog: unable to keep GPS ON");
    gpsHasFix = false;
    jeepneyStatus = "GPS ERROR";
  }
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

// =====================================================
// DISTANCE CALCULATION
// =====================================================
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

  double latitudeDifference =
    degreesToRadians(latitude2 - latitude1);

  double longitudeDifference =
    degreesToRadians(longitude2 - longitude1);

  double a =
    sin(latitudeDifference / 2.0) *
    sin(latitudeDifference / 2.0) +
    cos(degreesToRadians(latitude1)) *
    cos(degreesToRadians(latitude2)) *
    sin(longitudeDifference / 2.0) *
    sin(longitudeDifference / 2.0);

  double c =
    2.0 * atan2(sqrt(a), sqrt(1.0 - a));

  return earthRadiusMeters * c;
}

void updateCurrentStop() {
  if (!gpsHasFix || routeStopCount == 0) return;
  if (currentStopIndex >= 0) {
    RouteStop& stop = routeStops[currentStopIndex];
    if (distanceMeters(gpsLatitude, gpsLongitude, stop.latitude, stop.longitude) <= stop.radius + 15.0) return;
  }
  int nearest = -1;
  double nearestDistance = 1e9;
  for (int i = 0; i < routeStopCount; ++i) {
    const RouteStop& stop = routeStops[i];
    double distance = distanceMeters(gpsLatitude, gpsLongitude, stop.latitude, stop.longitude);
    if (distance <= stop.radius && distance < nearestDistance) {
      nearest = i;
      nearestDistance = distance;
    }
  }
  if (nearest == currentStopIndex) return;
  currentStopIndex = nearest;
  stopTransitionPending = true;
  if (nearest >= 0) {
    stopEnteredAt = millis();
    lcdPage = 0;
    lastVehicleSync = 0;
  }
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

  double entryDistance = distanceMeters(
    gpsLatitude,
    gpsLongitude,
    FUEL_ENTRY_LAT,
    FUEL_ENTRY_LON
  );

  double exitDistance = distanceMeters(
    gpsLatitude,
    gpsLongitude,
    FUEL_EXIT_LAT,
    FUEL_EXIT_LON
  );

  Serial.print("Fuel entry distance: ");
  Serial.print(entryDistance, 1);
  Serial.println(" meters");

  Serial.print("Fuel exit distance: ");
  Serial.print(exitDistance, 1);
  Serial.println(" meters");

  // Enter fueling mode.
  if (!fuelingMode &&
      entryDistance <= FUEL_RADIUS_METERS) {
    fuelingMode = true;
  }

  // Leave fueling mode.
  if (fuelingMode &&
      exitDistance <= FUEL_RADIUS_METERS) {
    fuelingMode = false;
  }

  // Fueling has the highest priority.
  if (fuelingMode) {
    jeepneyStatus = "FUELING";
    stoppedSince = 0;
    return;
  }

  // Jeepney is moving.
  if (gpsSpeedKmh > MOVEMENT_SPEED_KMH) {
    jeepneyStatus = "ACTIVE";
    stoppedSince = 0;
    return;
  }

  // Jeepney has just stopped.
  if (stoppedSince == 0) {
    stoppedSince = millis();
    jeepneyStatus = "ACTIVE";
    return;
  }

  // Jeepney has been stopped for at least 30 seconds.
  if (millis() - stoppedSince >= BREAK_DELAY) {
    jeepneyStatus = "BREAK TIME";
  } else {
    jeepneyStatus = "ACTIVE";
  }
}

bool parseGPSResponse(const String& response) {
  String gpsData = extractCGNSINFLine(response);

  if (gpsData.length() == 0) {
    Serial.println("No +CGNSINF line found");

    gpsHasFix = false;
    jeepneyStatus = "GPS ERROR";

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

  // Report an unexpected OFF state. The watchdog only reasserts ON; it does
  // not cycle the receiver through an OFF/restart sequence.
  if (runningStatus != 1) {
    Serial.println("GPS engine reported OFF");

    gpsHasFix = false;
    jeepneyStatus = "GPS ERROR";
    drawCurrentLCDPage();

    return false;
  }

  // GPS is running but has no satellite fix.
  if (fixStatus != 1) {
    gpsHasFix = false;
    jeepneyStatus = "NO FIX";

    Serial.println("GPS is ON, but has no fix");
    Serial.println("Place antenna outdoors facing upward");

    return false;
  }

  String latitudeText =
    getCSVField(gpsData, 3);

  String longitudeText =
    getCSVField(gpsData, 4);

  String speedText =
    getCSVField(gpsData, 6);

  if (latitudeText.length() == 0 ||
      longitudeText.length() == 0) {
    gpsHasFix = false;
    jeepneyStatus = "NO FIX";

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
    jeepneyStatus = "BAD GPS";
    return false;
  }

  gpsHasFix = true;

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
    jeepneyStatus = "SIM ERROR";
    return;
  }

  logSIM808Battery();

  String response =
    sendATCommand("AT+CGNSINF", 5000);

  if (response.indexOf("+CGNSINF:") < 0) {
    Serial.println("No GPS response received");

    String testResponse =
      sendATCommand("AT", 3000);

    if (testResponse.indexOf("OK") < 0) {
      sim808Available = false;
      gpsHasFix = false;
      jeepneyStatus = "SIM ERROR";
    } else {
      sim808Available = true;
      gpsHasFix = false;
      jeepneyStatus = "GPS ERROR";
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
// FIREBASE: one GPS device updates one existing vehicle document.
// Uses Firebase Auth ID tokens and the Firestore REST API over verified TLS.
// =====================================================
bool firebaseConfigured() {
  return String(FIREBASE_API_KEY) != "YOUR_FIREBASE_WEB_API_KEY" &&
         String(FIREBASE_DEVICE_EMAIL) != "YOUR_DEVICE_EMAIL" &&
         String(FIREBASE_DEVICE_PASSWORD) != "YOUR_DEVICE_PASSWORD" &&
         String(VEHICLE_DOCUMENT_ID) != "YOUR_JEEP_VEHICLE_DOCUMENT_ID" &&
         String(FIREBASE_ROOT_CA).indexOf("PASTE_GOOGLE_API_ROOT_CA_PEM_HERE") < 0;
}

bool clockReady() {
  if (time(nullptr) > 1700000000) return true;
  configTime(0, 0, "time.google.com", "pool.ntp.org");
  const unsigned long started = millis();
  while (time(nullptr) <= 1700000000 && millis() - started < 10000) {
    delay(250);
    yield();
  }
  return time(nullptr) > 1700000000;
}

bool signInFirebase() {
  if (!firebaseConfigured() || WiFi.status() != WL_CONNECTED || !clockReady()) {
    Serial.println("Firebase not configured, WiFi offline, or clock unavailable");
    return false;
  }

  BearSSL::WiFiClientSecure client;
  BearSSL::X509List trustAnchor(FIREBASE_ROOT_CA);
  client.setTrustAnchors(&trustAnchor);
  client.setTimeout(12000);

  HTTPClient http;
  const String url = String("https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=") + FIREBASE_API_KEY;
  if (!http.begin(client, url)) return false;
  http.setTimeout(12000);
  http.addHeader("Content-Type", "application/json");

  JsonDocument request;
  request["email"] = FIREBASE_DEVICE_EMAIL;
  request["password"] = FIREBASE_DEVICE_PASSWORD;
  request["returnSecureToken"] = true;
  String body;
  serializeJson(request, body);

  int code = http.POST(body);
  String response = http.getString();
  http.end();
  if (code != 200) {
    Serial.printf("Firebase sign-in failed (HTTP %d)\n", code);
    // Firebase's JSON error identifies issues such as EMAIL_NOT_FOUND,
    // INVALID_LOGIN_CREDENTIALS, or API-key configuration problems.
    Serial.println(response);
    return false;
  }

  JsonDocument result;
  if (deserializeJson(result, response)) {
    Serial.println("Firebase sign-in response was not valid JSON");
    return false;
  }
  String token = result["idToken"].as<String>();
  unsigned long expiresSeconds = result["expiresIn"].as<String>().toInt();
  if (token.isEmpty() || expiresSeconds < 120) return false;

  firebaseIdToken = token;
  firebaseTokenIssuedAt = millis();
  firebaseTokenLifetimeMs = (expiresSeconds - 60UL) * 1000UL;
  Serial.println("Firebase device signed in");
  return true;
}

bool firebaseTokenReady() {
  if (firebaseIdToken.length() > 0 &&
      millis() - firebaseTokenIssuedAt < firebaseTokenLifetimeMs) return true;

  if (lastFirebaseAuthAttempt != 0 &&
      millis() - lastFirebaseAuthAttempt < FIREBASE_AUTH_RETRY_MS) return false;
  lastFirebaseAuthAttempt = millis();
  firebaseIdToken = "";
  return signInFirebase();
}

void syncRouteStops() {
  if (WiFi.status() != WL_CONNECTED || !firebaseTokenReady()) return;
  BearSSL::WiFiClientSecure client;
  BearSSL::X509List trustAnchor(FIREBASE_ROOT_CA);
  client.setTrustAnchors(&trustAnchor);
  client.setTimeout(3000);
  HTTPClient http;
  const String url = String("https://firestore.googleapis.com/v1/projects/") +
      FIREBASE_PROJECT_ID + "/databases/(default)/documents/routes?pageSize=30";
  if (!http.begin(client, url)) return;
  http.setTimeout(3000);
  http.addHeader("Authorization", "Bearer " + firebaseIdToken);
  const int code = http.GET();
  const String response = code == 200 ? http.getString() : "";
  http.end();
  if (code == 401) firebaseIdToken = "";
  if (code != 200) {
    Serial.printf("Route sync failed (HTTP %d)\n", code);
    return;
  }
  JsonDocument document;
  if (deserializeJson(document, response)) return;
  int count = 0;
  for (JsonVariant item : document["documents"].as<JsonArray>()) {
    JsonVariant fields = item["fields"];
    if (!fields["active"]["booleanValue"].as<bool>() || fields["archived"]["booleanValue"].as<bool>()) continue;
    JsonVariant point = fields["location"]["geoPointValue"];
    if (point.isNull()) continue;
    String path = item["name"].as<String>();
    RouteStop& stop = routeStops[count];
    stop.id = path.substring(path.lastIndexOf('/') + 1);
    stop.name = fields["name"]["stringValue"].as<String>();
    stop.latitude = point["latitude"].as<double>();
    stop.longitude = point["longitude"].as<double>();
    stop.radius = fields["proximityRadius"]["integerValue"].as<String>().toDouble();
    if (stop.radius <= 0) stop.radius = fields["proximityRadius"]["doubleValue"].as<double>();
    if (stop.radius <= 0) stop.radius = 40.0;
    if (++count >= 30) break;
  }
  routeStopCount = count;
  currentStopIndex = -1;
  updateCurrentStop();
}

void syncVehicleData() {
  if (WiFi.status() != WL_CONNECTED || !firebaseTokenReady()) return;
  BearSSL::WiFiClientSecure client;
  BearSSL::X509List trustAnchor(FIREBASE_ROOT_CA);
  client.setTrustAnchors(&trustAnchor);
  client.setTimeout(12000);
  const String url = String("https://firestore.googleapis.com/v1/projects/") +
      FIREBASE_PROJECT_ID + "/databases/(default)/documents/vehicles/" +
      VEHICLE_DOCUMENT_ID;
  HTTPClient http;
  if (!http.begin(client, url)) return;
  http.setTimeout(12000);
  http.addHeader("Authorization", "Bearer " + firebaseIdToken);
  const int code = http.GET();
  const String response = code == 200 ? http.getString() : "";
  http.end();
  if (code == 401) firebaseIdToken = "";
  if (code != 200) {
    Serial.printf("Firestore vehicle sync failed (HTTP %d)\n", code);
    return;
  }
  JsonDocument document;
  if (deserializeJson(document, response)) return;
  String status = document["fields"]["status"]["stringValue"].as<String>();
  status.toUpperCase();
  if (status == "ACTIVE" || status == "IDLE" || status == "BREAK") {
    vehicleStatus = status;
  }
  onboardCount = document["fields"]["onBoardPassengers"]["integerValue"].as<String>().toInt();
  outboardCount = document["fields"]["outBoardPassengers"]["integerValue"].as<String>().toInt();
  expectedOffCount = 0;
  if (currentStopIndex >= 0) {
    const String routeId = routeStops[currentStopIndex].id;
    expectedOffCount = document["fields"]["expectedOutboardByStop"]["mapValue"]["fields"][routeId]["integerValue"].as<String>().toInt();
  }
  drawCurrentLCDPage();
}

void uploadVehicleLocation() {
  if (!gpsHasFix || WiFi.status() != WL_CONNECTED || !firebaseTokenReady()) return;

  char gpsTimestamp[25];
  const time_t nowUtc = time(nullptr);
  struct tm* utc = gmtime(&nowUtc);
  if (utc == nullptr ||
      strftime(gpsTimestamp, sizeof(gpsTimestamp), "%Y-%m-%dT%H:%M:%SZ", utc) == 0) {
    Serial.println("GPS upload skipped: clock unavailable");
    return;
  }

  String body;
  {
    JsonDocument payload;
    payload["fields"]["location"]["geoPointValue"]["latitude"] = gpsLatitude;
    payload["fields"]["location"]["geoPointValue"]["longitude"] = gpsLongitude;
    payload["fields"]["latitude"]["doubleValue"] = gpsLatitude;
    payload["fields"]["longitude"]["doubleValue"] = gpsLongitude;
    payload["fields"]["speedKmh"]["doubleValue"] = gpsSpeedKmh;
    payload["fields"]["currentStopRouteId"]["stringValue"] =
        currentStopIndex >= 0 ? routeStops[currentStopIndex].id : "";
    payload["fields"]["lastGpsAt"]["timestampValue"] = gpsTimestamp;
    serializeJson(payload, body);
  }
  if (body.isEmpty()) {
    Serial.println("GPS upload skipped: JSON allocation failed");
    return;
  }

  BearSSL::WiFiClientSecure client;
  BearSSL::X509List trustAnchor(FIREBASE_ROOT_CA);
  client.setTrustAnchors(&trustAnchor);
  client.setTimeout(12000);

  // updateMask preserves registration data, and exists=true prevents creating
  // a second vehicle if the configured document ID is wrong or was deleted.
  const String url = String("https://firestore.googleapis.com/v1/projects/") +
      FIREBASE_PROJECT_ID + "/databases/(default)/documents/vehicles/" +
      VEHICLE_DOCUMENT_ID +
      "?updateMask.fieldPaths=location&updateMask.fieldPaths=latitude" +
      "&updateMask.fieldPaths=longitude&updateMask.fieldPaths=speedKmh" +
      "&updateMask.fieldPaths=currentStopRouteId" +
      "&updateMask.fieldPaths=lastGpsAt" +
      "&currentDocument.exists=true";

  HTTPClient http;
  if (!http.begin(client, url)) return;
  http.setTimeout(12000);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", "Bearer " + firebaseIdToken);

  int code = http.PATCH(body);
  http.end();
  if (code == 200) {
    Serial.printf("Vehicle GPS uploaded to Firestore vehicles/%s at %s\n",
                  VEHICLE_DOCUMENT_ID, gpsTimestamp);
  } else {
    Serial.printf("Firestore GPS upload failed (HTTP %d)\n", code);
    if (code == 401) firebaseIdToken = "";
  }
}

// =====================================================
// SETUP
// =====================================================
void setup() {
  Serial.begin(115200);
  delay(500);

  Serial.println();
  Serial.println("SIM808 GPS Tracker Starting");

  // LCD I2C: SDA D2, SCL D1.
  Wire.begin(D2, D1);

  lcd.begin();
  lcd.clear();

  jeepneyStatus = "STARTING";
  displayJeepInformation();

  // SIM808 communicates at 9600 baud.
  sim808.begin(9600);
  delay(2000);

  connectWiFi();
  syncRouteStops();
  syncVehicleData();

  initializeSIM808();

  if (sim808Available) {
    jeepneyStatus = "GPS STARTING";
    drawCurrentLCDPage();

    startGPS();

    delay(2000);

    fetchGPS();
    updateCurrentStop();
    uploadVehicleLocation();
    lastGPSUpload = millis();
  } else {
    jeepneyStatus = "SIM ERROR";
  }

  lastGPSRequest = millis();
  lastGPSWatchdog = millis();
  lastLCDPageSwitch = millis();

  lcdPage = 0;
  drawCurrentLCDPage();
}

// =====================================================
// MAIN LOOP
// =====================================================
void loop() {
  maintainWiFi();
  if (millis() - lastRouteSync >= ROUTE_SYNC_INTERVAL) {
    lastRouteSync = millis();
    syncRouteStops();
  }
  if (millis() - lastVehicleSync >=
      (currentStopIndex >= 0 ? STOP_VEHICLE_SYNC_INTERVAL : VEHICLE_SYNC_INTERVAL)) {
    lastVehicleSync = millis();
    syncVehicleData();
  }
  retrySIM808();
  keepGPSOn();
  updateLCDPages();

  if (sim808Available &&
      millis() - lastGPSRequest >=
      GPS_REQUEST_INTERVAL) {
    lastGPSRequest = millis();

    fetchGPS();
    updateCurrentStop();
    drawCurrentLCDPage();
  }

  if (gpsHasFix && (stopTransitionPending ||
      millis() - lastGPSUpload >= GPS_UPLOAD_INTERVAL)) {
    lastGPSUpload = millis();
    uploadVehicleLocation();
    stopTransitionPending = false;
    updateLCDPages();
  }

  yield();
}
