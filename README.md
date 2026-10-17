# 🌧 Rain Machine

**Three piezo disks in a plastic bag, listening to actual rain.**

Each raindrop that hits a piezo is sent over serial to a Processing sketch, where it kicks a blocky height field into expanding ripples and rings out as one note of a three‑note chord — depending on which sensor was hit.

No samples. No stored animation. No preset loop. The rain is both the input and the score.

> *Recorded on a rainy October Saturday in Beijing, with a laptop under an umbrella and a breadboard in a Ziploc bag.*

---

## Concept

Most generative rain visuals are driven by a noise function or a recorded loop. This one isn't. It listens to the actual weather, translates each physical impact into a serial event, and lets a wave equation spread the disturbance across a grid.

The machine has no memory of the previous drop. It only reacts to the next one. Remove the rain and the field goes flat on its own.

The setup is intentionally fragile — condensation inside the bag, cling film dulling the sensors, one loose jumper wire — and that instability is part of the piece. Every run is a negotiation with the weather.

---

## Bill of Materials

| Qty | Part | Notes |
|----:|------|-------|
| 1 | Arduino Uno (or compatible) | Any board with 3 analog inputs |
| 3 | Piezo disks (27 mm, thin brass) | The flat round kind, not a buzzer module |
| 3 | 1 MΩ resistors | Bleed resistor across each piezo |
| 3 | Jumper wires | Sensor → breadboard |
| 1 | Breadboard | |
| 1 | Laptop | Running Processing 4 |
| — | Cling film | Waterproofing layer over the disks |
| — | Ziploc bag + tape | Housing for the breadboard and Arduino |
| — | Umbrella | For the human, not the machine |

---

## Wiring

### Pin map

| Sensor | Analog pin | Bleed resistor | Signal event |
|--------|-----------|----------------|--------------|
| Piezo 0 | `A0` | 1 MΩ → GND | `D0` |
| Piezo 1 | `A1` | 1 MΩ → GND | `D1` |
| Piezo 2 | `A2` | 1 MΩ → GND | `D2` |

### Schematic

```
                        ┌──────────────────────────────┐
                        │          ARDUINO UNO         │
                        │                              │
   Piezo 0 ────────────►│ A0                           │
   Piezo 1 ────────────►│ A1                           │
   Piezo 2 ────────────►│ A2                           │
                        │                              │
                        │ GND ────┬────────────────────┼──► common GND rail
                        │         │                    │
                        │ USB ────┴──────► Laptop      │
                        │                              │
                        └──────────────────────────────┘
```

### Per‑piezo detail (repeat ×3)

```
        Piezo disk                        Arduino
     ┌───────────────┐
     │   ┌───────┐   │
     │   │   ●   │   │   red wire   ────────────►  A0 / A1 / A2
     │   └───────┘   │
     │               │   black wire ────────────►  GND
     └───────────────┘
          │       │
          └───────┴──── 1 MΩ resistor across red and black
```

### Why the 1 MΩ resistor?

A piezo element generates a voltage spike when struck, but the charge has nowhere to go — without a bleed path the analog pin can sit "high" for seconds after a single impact and you miss every subsequent drop. The 1 MΩ resistor discharges the element between hits.

### Waterproofing

The piezo disks are **not waterproof** — exposed electrodes and rain are a short circuit waiting to happen. For the field test:

1. **Wrap each disk tightly in cling film** — stretched like a drumhead, not loose. Loose film absorbs the impact and the sensor goes deaf.
2. **Seal the wire entry** with hot glue or silicone at the *edge* of the disk, never over the face.
3. **House the breadboard and Arduino in a Ziploc bag**, taped around the sensor end where the three piezos stick out.
4. **Expect condensation.** Silica gel packets taped inside the bag help a lot.

A cling film wrap adds mass and compliance, so expect to drop `THRESHOLD` by roughly half compared to bare disks.

---

## Arduino Sketch

Non‑blocking drop detection for all three sensors. No `delay()` anywhere, so the loop runs thousands of times per second and can catch the short spike of a raindrop.

Each sensor has its own debounce timer so a single physical drop doesn't get counted as a burst.

```cpp
const int PIEZO_PINS[] = {A0, A1, A2};
const int NUM_SENSORS = 3;

const int THRESHOLD = 15;               // 10–30 for a cling-film-wrapped piezo
const unsigned long DEBOUNCE_MS = 100;  // min time between drops on one sensor

unsigned long lastDropTime[NUM_SENSORS] = {0, 0, 0};

void setup() {
  Serial.begin(115200);
}

void loop() {
  unsigned long now = millis();

  for (int i = 0; i < NUM_SENSORS; i++) {
    int value = analogRead(PIEZO_PINS[i]);

    if (value > THRESHOLD && (now - lastDropTime[i]) > DEBOUNCE_MS) {
      Serial.print('D');
      Serial.println(i);        // "D0", "D1", "D2"
      lastDropTime[i] = now;
    }
  }

  // no delay — the loop must stay fast
}
```

### Tuning in the field

1. Upload the sketch, open the Serial Monitor at **115200**.
2. Watch the idle readings — they should hover near 0.
3. Drip water onto each wrapped disk from ~30 cm.
4. Set `THRESHOLD` to about **30–50 % above the highest idle reading**.
5. Leave it outdoors in dry conditions for an hour. If phantom drops appear, raise `THRESHOLD` or increase `DEBOUNCE_MS`.

---

## Processing Sketch

Requires Processing 4 and the **Sound** library (`Sketch → Import Library → Manage Libraries → Sound`).

```java
import processing.serial.*;
import processing.sound.*;

// ---------- Serial ----------
Serial myPort;

// ---------- Grid ----------
int cols = 48, rows = 32;
float cellW, cellH;
float[][] current, previous;

// ---------- Sound ----------
final int NUM_SENSORS = 3;
SinOsc[] tones = new SinOsc[NUM_SENSORS];
float[]  envelopes  = new float[NUM_SENSORS];
float[]  sensorFreq = { 440.0, 554.37, 659.25 };   // A4, C#5, E5

final float DROP_STRENGTH = 50.0;
final float DAMPING       = 0.98;
final float SOUND_DECAY   = 0.92;
final float MAX_AMP       = 0.15;   // 3 voices × 0.15 = safe

void setup() {
  fullScreen();
  // size(960, 640);   // fallback if fullScreen() misbehaves

  cellW = width  / (float) cols;
  cellH = height / (float) rows;
  current  = new float[cols][rows];
  previous = new float[cols][rows];

  // ----- Serial: pick by name, fail gracefully -----
  printArray(Serial.list());
  String portName = null;
  for (String s : Serial.list()) {
    if (s.contains("usbmodem") || s.contains("usbserial") || s.contains("COM")) {
      portName = s; break;
    }
  }
  if (portName == null) {
    println("No Arduino found — running without serial.");
  } else {
    myPort = new Serial(this, portName, 115200);
    myPort.bufferUntil('\n');
    println("Connected to " + portName);
  }

  // ----- Sound: one oscillator per sensor -----
  new Sound(this);
  for (int i = 0; i < NUM_SENSORS; i++) {
    tones[i] = new SinOsc(this);
    tones[i].freq(sensorFreq[i]);
    tones[i].amp(0);
    tones[i].play();
  }
}

void draw() {
  background(20, 40, 80);   // deep water blue

  // ----- Evolve automaton -----
  float[][] tmp = previous;
  previous = current;
  current  = tmp;

  for (int x = 1; x < cols-1; x++) {
    for (int y = 1; y < rows-1; y++) {
      current[x][y] = (previous[x-1][y] + previous[x+1][y] +
                       previous[x][y-1] + previous[x][y+1]) * 0.5
                       - current[x][y];
      current[x][y] *= DAMPING;
    }
  }

  // ----- Draw blocky grid -----
  noStroke();
  for (int x = 0; x < cols; x++) {
    for (int y = 0; y < rows; y++) {
      float h = constrain(current[x][y], -20, 20);
      float brightness = map(h, -20, 20, 0, 255);
      fill(brightness, 180, 255 - brightness);
      rect(x * cellW, y * cellH, cellW - 1, cellH - 1);
    }
  }

  // ----- Sound: per-voice envelope -----
  for (int i = 0; i < NUM_SENSORS; i++) {
    if (envelopes[i] > 0.001) {
      envelopes[i] *= SOUND_DECAY;
      tones[i].amp(envelopes[i] * MAX_AMP);
    } else {
      envelopes[i] = 0;
      tones[i].amp(0);
    }
  }
}

void serialEvent(Serial p) {
  String line = p.readStringUntil('\n');
  if (line == null) return;
  line = trim(line);
  if (!line.startsWith("D")) return;

  try {
    int sensor = Integer.parseInt(line.substring(1).trim());
    if (sensor >= 0 && sensor < NUM_SENSORS) triggerDrop(sensor);
  } catch (NumberFormatException e) {
    // ignore malformed lines
  }
}

void triggerDrop(int sensor) {
  int col = int(map(sensor, 0, NUM_SENSORS - 1, 8, cols - 8));
  int row = int(random(4, rows - 4));

  current[col][row] += DROP_STRENGTH;   // += not =
  envelopes[sensor]   = 1.0;
}
```

### How the visual works

The grid stores a `float` height per cell. Every frame, each cell's new height is computed from its four neighbours:

```
new = (north + south + east + west) / 2 - old
```

That's the discrete wave equation. A drop injects a large positive value at a cell, the equation propagates it outward, and `DAMPING` (0.98) slowly bleeds energy away. Rendering each cell as a filled `rect()` with a 1 px gap gives the blocky, pixel‑puddle look.

### How the sound works

Three `SinOsc` voices, one per sensor, tuned to A4 / C#5 / E5. Each drop resets that voice's envelope to `1.0`; the envelope multiplies by `SOUND_DECAY` every frame and drives the oscillator amplitude. `MAX_AMP` is kept at 0.15 per voice so three simultaneous drops don't clip.

---

## How to Run

1. **Wire** the piezos per the schematic above.
2. **Upload** the Arduino sketch.
3. **Close the Arduino Serial Monitor** — Processing needs exclusive access to the port.
4. Open the Processing sketch, install the **Sound** library if you haven't.
5. Run it. The console prints the port it connected to.
6. If it prints `No Arduino found`, copy the port list from the console and adjust the `contains(...)` filter to match your device (Linux often shows `ttyACM…`, clones show `cu.wchusbserial…`).

---

## Testing Without Hardware

If you just want to see the visuals and hear the sound before going outdoors, replace the serial block with a random drop generator at the top of `draw()`:

```java
float dropRate = 8.0;   // drops per second

// inside draw(), before the automaton update:
if (frameRate > 0 && random(1) < dropRate / frameRate) {
  triggerDrop(int(random(NUM_SENSORS)));
}
```

`2.0` gives a drizzle, `20–40` a downpour. Everything else stays the same.

---

## Tuning Reference

| Constant | Where | Effect |
|---|---|---|
| `THRESHOLD` | Arduino | Lower = more sensitive. Cling film wrapped disks usually need ~10–15. |
| `DEBOUNCE_MS` | Arduino | Higher = fewer phantom triggers from ringing or wind. |
| `DROP_STRENGTH` | Processing | How violent each drop is — brighter flash, louder plink, bigger ripple. |
| `DAMPING` | Processing | `0.95` = snappy ripples, `0.995` = long watery tails. |
| `SOUND_DECAY` | Processing | `0.85` = short plink, `0.95` = long bell. |
| `MAX_AMP` | Processing | Keep ≤ 0.2 per voice with three oscillators. |
| `sensorFreq` | Processing | The chord. Try `{329.63, 392.00, 493.88}` for something darker. |
| `cols` / `rows` | Processing | 48×32 is chunky; 96×64 is finer. Scale with `width / 20.0` if you want constant apparent cell size across displays. |

---

## Field Notes

Things learned the hard way, in the rain:

- **Cling film is consumable.** It works for a session or two, then fogs from the inside. Plan on replacing it, or upgrade to a silicone conformal coating or a thin cast urethane layer for a permanent install.
- **Wind causes false drops.** Film flapping generates small signals. A foam backing behind the disk helps; so does raising `DEBOUNCE_MS`.
- **Full screen ≠ full screen on every platform.** On some Linux window managers `fullScreen()` opens an oddly placed window. `size(displayWidth, displayHeight); surface.setLocation(0, 0);` is a reliable fallback.
- **Close the Serial Monitor before running Processing.** Otherwise `new Serial(...)` throws `PortInUseException` and the sketch dies on launch.
- **The fragility is the point.** Condensation, dulled sensors, a loose wire — each one is a reminder that self‑reference in hardware is a negotiation, not a guarantee.

---

## Credits

Built with an Arduino Uno and Processing 4 (Sound library). The concept grew out of an earlier project, **Physical Quine**, in which a servo reproduced the taps it heard so that the system's output became its own next instruction. Rain Machine keeps that feedback structure but opens it to the weather.

---

## License

Code: MIT. Concept, documentation, and any video/imagery: [CC BY‑NC‑SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) — pick whichever fits how you want it reused, or delete this section.


 
