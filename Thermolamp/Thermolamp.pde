
/*

4 Digit 7 Segment display from Sparkfun
http://www.sparkfun.com/commerce/product_info.php?products_id=9480
 1: Digit 1	   16: B
 2: Digit 2	   15: G
 3: D	           14: A
 4: Colon Anode	   13: C
 5: E	           12: Colon Cathode
 6: Digit 3	   11: F
 7: Decimal Point  10: Apostrophe Anode
 8: Digit 4	   9:  Apostrophe Cathode
 
8 Bit Shift Register

 1: display's B    16: 5V    
 2: display's C    15: display's A
 3: display's D    14: arduino's dataPin
 4: display's E    13: Gnd
 5: display's F    12: arduino's latchPin
 6: display's G    11: arduino's clockPin
 7: display's DP   10: 5V
 8: Gnd            9:  none
 
 *************
 Display's Cathode goes to ground via resistor
 Display's Anode goes to digital out
 Digit pins go to digital out via resistor
 Segment pins (A-G) go to digital out or shift register out (0 is on)

original shift reg code:
http://arduino.cc/en/Tutorial/ShftOut13

helpful schematic:
http://www.modxhost.com/595and4021.jpg

*/

#include <OneWire.h>
#include "Wire.h"
#include "BlinkM_funcs.h"

#define blinkm_addr 0x00

int latchPin = 8;  //Pin connected to ST_CP of 74HC595 (aka RCLK)
int clockPin = 12;  //Pin connected to SH_CP of 74HC595 (aka SRCLK)
int dataPin = 11;  //Pin connected to DS of 74HC595 (aka SER)

int digit1Pin = 5;  //can't use pin 1 since it's TX?
int digit2Pin = 2;
int digit3Pin = 3;
int digit4Pin = 4;

byte data;
byte dataArray[13];

const int MINUS_IDX = 10;
const int CELCIUS_IDX = 11;
const int FARENHEIT_IDX = 12;

unsigned long currentTime = 0;
unsigned long prevTempTime = 0;
unsigned long prevLampTime = 0;
int thermoValue;
int displayTemp;
int hueValue;
int hueValueDirection = 1;  //1 is forward, -1 is back

// DS18S20 Temperature chip i/o
OneWire ds(6);  // on pin 10

int buttonPin = 9;
int buttonValue = 0;
unsigned long buttonStartTime = 0;
unsigned long buttonTime = 0;
boolean buttonPressed = false;
boolean buttonLongPressed = false;
char scale = 'C';
int mode;
int numModes = 4;

void setup(){
  pinMode(digit1Pin, OUTPUT);
  pinMode(digit2Pin, OUTPUT);
  pinMode(digit3Pin, OUTPUT);
  pinMode(digit4Pin, OUTPUT);
 
  pinMode(latchPin, OUTPUT);
  
  pinMode(buttonPin, INPUT);

  Serial.begin(9600);

  //      A
  //    F   B
  //      G
  //    E   C
  //      D   dp (H)
  //
  //  In binary representation, right most digit is A
  
  dataArray[0] = B11000000;
  dataArray[1] = B11111001;
  dataArray[2] = B10100100;
  dataArray[3] = B10110000; 
  dataArray[4] = B10011001; 
  dataArray[5] = B10010010; 
  dataArray[6] = B10000010; 
  dataArray[7] = B11111000; 
  dataArray[8] = B10000000; 
  dataArray[9] = B10010000; 
  
  //temperature specific characters
  dataArray[MINUS_IDX] = B10111111;  // minus sign
  dataArray[CELCIUS_IDX] = B11000110;  // C
  dataArray[FARENHEIT_IDX] = B10001110;  // F
  
  BlinkM_beginWithPower();
  BlinkM_stopScript(blinkm_addr);  
  BlinkM_setFadeSpeed(blinkm_addr, 20);
  //fade to max saturation and brightness first
  BlinkM_fadeToHSB(blinkm_addr, 210, 255, 255);
  delay(1000);
  
  int i = 1;
  while (i <= 220){
    BlinkM_fadeToHSB(blinkm_addr, (i + 210) % 255, 255, 255);
    delay(10);
    i++;
  }
  
  mode = 0;
   
}

void loop(){
  
  currentTime = millis();
  buttonValue = digitalRead(buttonPin);
  
  if (buttonValue == 1){
    if (buttonPressed == false) {
      buttonPressed = true;
      buttonStartTime = currentTime; 
    } else {
      buttonTime = currentTime - buttonStartTime; 
      if (buttonTime > 1500) {
        buttonPressed = false;
        buttonLongPressed = true;
        buttonTime = 0;
        longPressEvent();
      }
    } 
   
  } else {
    if (buttonPressed == true){
      buttonPressed = false;
      if (buttonLongPressed) {
        buttonLongPressed = false;
      } else if (buttonTime < 1500) {
        shortPressEvent();
      }
    } 
  }
  
  //every .5 seconds, refresh the lamp
  if (prevLampTime + 50 < currentTime){
    refreshLamp(); 
    prevLampTime = currentTime;
  }
  
  //every 10 seconds, refresh the temp reading
  if (prevTempTime + 10000 < currentTime || thermoValue == 999 || prevTempTime == 0){
    thermoValue = getTemp(); 
    if (thermoValue != 999){
      //Serial.print("therm:");Serial.println(thermoValue);
      //Serial.print("hue:");Serial.println(hueValue);
      prevTempTime = currentTime;
    } 
  }
  
  if (thermoValue != 999){
    if (scale == 'F'){
      displayTemp = (thermoValue * 9)/5 + 32; 
    } else {
      displayTemp = thermoValue; 
    }
    setDisplayTemp(displayTemp, scale);
  }
  
}

void getHue(int thermoValue){
  if (mode == 0) {
    hueValue = (map(thermoValue, -20, 40, 220, 1) + 210) % 255; 
  } else if (mode == 1){
    hueValue = (map(thermoValue, -20, 40, 1, 220) + 210) % 255;
  } else if (mode == 2){
    int hueValueOriginal = (map(thermoValue, -20, 40, 220, 1) + 210) % 255; 
    if ((hueValue > hueValueOriginal + 20) | (hueValue < hueValueOriginal - 20)) {
      hueValue = hueValueOriginal + (20 * hueValueDirection);
      hueValueDirection = hueValueDirection * -1;
    } else {
      hueValue = hueValue + hueValueDirection;
    }  
  } else if (mode == 3){
    int hueValueOriginal = (map(thermoValue, -20, 40, 1, 220) + 210) % 255; 
    if ((hueValue > hueValueOriginal + 20) | (hueValue < hueValueOriginal - 20)) {
      hueValue = hueValueOriginal + (20 * hueValueDirection);
      hueValueDirection = hueValueDirection * -1;
    } else {
      hueValue = hueValue + hueValueDirection;
    }  
    
  }
}

void refreshLamp(){
  getHue(thermoValue);
  BlinkM_fadeToHSB(blinkm_addr, hueValue, 255, 255); 
}

void longPressEvent(){
  mode = (mode + 1) % numModes; 
  Serial.print("mode:");Serial.println(mode);
  Serial.print("hueValue:");Serial.println(hueValue);
  //Serial.print("hueValueOriginal:");Serial.println(hueValueOriginal);
  thermoValue = 999;

}

void shortPressEvent(){
  if (scale == 'C') {
    scale = 'F';
  } else {
    scale = 'C';
  }  
}

int getTemp(){
  int HighByte, LowByte, TReading, SignBit, Tc_100, Whole, Fract, temperature;

  temperature = 999; //this is an invalid reading

  byte i;
  byte present = 0;
  byte data[12];
  byte addr[8];
 
  if ( !ds.search(addr)) {
      ds.reset_search();
      return temperature;
  }
 
  for( i = 0; i < 8; i++) {
  }
 
  if ( OneWire::crc8( addr, 7) != addr[7]) {
      //Serial.print("CRC is not valid!\n");
      return temperature;
  }
 
  if ( addr[0] != 0x28) {
      //Serial.print("Device is not a DS18B20 family device.\n");
      return temperature;
  }
 
  ds.reset();
  ds.select(addr);
  ds.write(0x44,1);         // start conversion, with parasite power on at the end
 
  //delay(1000);     // maybe 750ms is enough, maybe not
  // we might do a ds.depower() here, but the reset will take care of it.
 
  present = ds.reset();
  ds.select(addr);    
  ds.write(0xBE);         // Read Scratchpad
 
  for ( i = 0; i < 9; i++) {           // we need 9 bytes
    data[i] = ds.read();
  }

  LowByte = data[0];
  HighByte = data[1];
  TReading = (HighByte << 8) + LowByte;
  SignBit = TReading & 0x8000;  // test most sig bit
  if (SignBit) // negative
  {
    TReading = (TReading ^ 0xffff) + 1; // 2's comp
  }
  Tc_100 = (6 * TReading) + TReading / 4;    // multiply by (100 * 0.0625) or 6.25

  Whole = Tc_100 / 100;  // separate off the whole and fractional portions
  Fract = Tc_100 % 100;

  temperature = Whole;
  if (SignBit) // If its negative
  {
     temperature = temperature * -1;
  }
  
  return temperature;
  
  /*
  Serial.print(Whole);
  Serial.print(".");
  if (Fract < 10)
  {
     Serial.print("0");
  }
  Serial.print(Fract);

  Serial.print("\n");
  */

}

void setDisplayTemp(int temp, char scale){
  //temp must be between -99 and 999 in either scale to fit the display 
  //put in a check here later
  boolean negative = false;
  if (temp < 0)
    negative = true;
  temp = abs(temp);
  
  if (scale == 'F'){
    setDigit(digit4Pin, FARENHEIT_IDX);
  } else if (scale == 'C'){
    setDigit(digit4Pin, CELCIUS_IDX);
  }
  
  setDigit(digit3Pin, temp % 10);
  temp /= 10;
  if (temp >= 1){
    setDigit(digit2Pin, temp % 10);
    temp /= 10;
    if (temp >= 1){
      setDigit(digit1Pin, temp % 10);
    }
  }
  if (negative){
    setDigit(digit1Pin, MINUS_IDX); 
  }
}

void setDigit(int digitPin, int value){
  
    digitalWrite(latchPin, 0);
    shiftOut(dataPin, clockPin, dataArray[value]);  
    digitalWrite(latchPin, 1);
    
    digitalWrite(digitPin, HIGH);
    delay(1);
    digitalWrite(digitPin, LOW);   
}


void shiftOut(int myDataPin, int myClockPin, byte myDataOut) {
  // This shifts 8 bits out MSB first, 
  //on the rising edge of the clock,
  //clock idles low

  //internal function setup
  int i=0;
  int pinState;
  pinMode(myClockPin, OUTPUT);
  pinMode(myDataPin, OUTPUT);

  //clear everything out just in case to
  //prepare shift register for bit shifting
  digitalWrite(myDataPin, 0);
  digitalWrite(myClockPin, 0);

  //for each bit in the byte myDataOut�
  //NOTICE THAT WE ARE COUNTING DOWN in our for loop
  //This means that %00000001 or "1" will go through such
  //that it will be pin Q0 that lights. 
  for (i=7; i>=0; i--)  {
    digitalWrite(myClockPin, 0);

    //if the value passed to myDataOut and a bitmask result 
    // true then... so if we are at i=6 and our value is
    // %11010100 it would the code compares it to %01000000 
    // and proceeds to set pinState to 1.
    if ( myDataOut & (1<<i) ) {
      pinState= 1;
    }
    else {	
      pinState= 0;
    }

    //Sets the pin to HIGH or LOW depending on pinState
    digitalWrite(myDataPin, pinState);
    //register shifts bits on upstroke of clock pin  
    digitalWrite(myClockPin, 1);
    //zero the data pin after shift to prevent bleed through
    digitalWrite(myDataPin, 0);
  }

  //stop shifting
  digitalWrite(myClockPin, 0);
}



