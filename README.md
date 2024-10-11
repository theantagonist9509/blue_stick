# BlueStick

A simple Bluetooth LE analog joystick app for communicating with hobby electronics components like the HM-10 blutooth module, built using the Flutter framework

NOTE: This app will NOT work with bluetooth modules like the HC-05; those are based on the Bluetooth Classic protocol while, for example, the HM-10 is based on the Bluetooth LE protocol.

## Usage

When connected to a supported receiver,
- If the joystick is idle, no data is sent
- Otherwise, the x and y coordinates of the joystick (i.e., two float32 values ranging [-1, 1]) are sent in little endian format (i.e., LSB sent first) in 100 ms intervals
