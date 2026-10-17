const int PIEZO_PINS[] = {A0, A1, A2};
const int NUM_SENSORS = 3;

const int THRESHOLD = 15;          // Lower for rain (test 10–30)
const unsigned long DEBOUNCE_MS = 100; // Minimum time between drops on the same sensor

unsigned long lastDropTime[NUM_SENSORS] = {0, 0, 0};

void setup() {
  Serial.begin(115200); // Fast baud for responsive streaming
}

void loop() {
  unsigned long now = millis();

  for (int i = 0; i < NUM_SENSORS; i++) {
    int value = analogRead(PIEZO_PINS[i]);

    // Non-blocking debounce: only register if enough time has passed
    if (value > THRESHOLD && (now - lastDropTime[i]) > DEBOUNCE_MS) {
      Serial.print('D');
      Serial.println(i);   // e.g., "D0", "D1", "D2"
      lastDropTime[i] = now;
    }
  }

  // No delay — the loop runs thousands of times per second
}