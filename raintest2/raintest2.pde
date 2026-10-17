import processing.sound.*;

// ---------- Grid ----------
int cols = 48, rows = 32;
float cellW, cellH;
float[][] current, previous;

// ---------- Sound ----------
final int NUM_SENSORS = 3;
SinOsc[] tones = new SinOsc[NUM_SENSORS];
float[]  envelopes = new float[NUM_SENSORS];
float[]  sensorFreq = { 440.0, 554.37, 659.25 };   // A4, C#5, E5

final float DROP_STRENGTH = 50.0;
final float DAMPING       = 0.98;
final float SOUND_DECAY   = 0.92;
final float MAX_AMP       = 0.15;   // 3 voices × 0.15 = safe

// ---------- Random drops ----------
float dropRate = 8.0;   // drops per second (all sensors combined)

void setup() {
  fullScreen();
  cellW = width  / (float) cols;
  cellH = height / (float) rows;
  current  = new float[cols][rows];
  previous = new float[cols][rows];

  new Sound(this);
  for (int i = 0; i < NUM_SENSORS; i++) {
    tones[i] = new SinOsc(this);
    tones[i].freq(sensorFreq[i]);
    tones[i].amp(0);
    tones[i].play();
  }
}

void draw() {
  background(20, 40, 80);

  // ----- Random drop generator -----
  if (frameRate > 0 && random(1) < dropRate / frameRate) {
    triggerDrop(int(random(NUM_SENSORS)));
  }

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

// ---------- Drop trigger ----------
void triggerDrop(int sensor) {
  int col = int(map(sensor, 0, NUM_SENSORS - 1, 8, cols - 8));
  int row = int(random(4, rows - 4));

  current[col][row] += DROP_STRENGTH;
  envelopes[sensor]   = 1.0;
}
