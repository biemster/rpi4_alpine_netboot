#!/usr/bin/env python3
# apk add py3-pip py3-libgpiod
# pip install apa102-gpiod
import gpiod
import apa102_gpiod.apa102 as apa102
from time import sleep

nupdates = 100 # number of updates to the strip before shutting down
update_interval = 0.1 # seconds

# power on the strip by setting gpio 5 high
gpio5 = gpiod.Chip('/dev/gpiochip0').get_line(5)
gpio5.request(consumer='leds.py', type=gpiod.LINE_REQ_DIR_OUT, default_val=0)
gpio5.set_value(1)

# we have 12 LEDs on gpiochip0, connected to SPI0 MOSI (GPIO10) and CLK (GPIO11)
nleds = 12
pin_clk = 11
pin_data = 10
leds = apa102.APA102('/dev/gpiochip0', nleds, pin_clk, pin_data, True)

# set colors
colors = [(255,0,0),(0,255,0),(0,0,225)] * (nleds//3)
brightness = [1] * nleds # in range(32)
for u in range(nupdates):
    for led in range(nleds):
        leds[(led+u) % nleds] = apa102.LedOutput(brightness[led], *colors[led])
    leds.commit()
    sleep(update_interval)

# shut down
leds.close()
gpio5.set_value(0)