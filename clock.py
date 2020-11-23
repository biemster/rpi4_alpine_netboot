#!/usr/bin/env python3
# apk add py3-pip py3-libgpiod
# pip install apa102-gpiod
import gpiod
import apa102_gpiod.apa102 as apa102
from time import sleep, localtime

NLEDS = 12
UPDATE_INTERVAL = 5 # in seconds
SECONDS_HAND = False

orientation = 'E' # N,E,S,W = direction of top (=seeed label)
hour_color = (2,0,2)
minute_color = (0,0,20)
second_color = (2,2,2)
brightness = 1

current_face = [(0,0,0)] * NLEDS

def poweron():
    # power on the strip by setting gpio 5 high
    gpio5_chip = gpiod.Chip('/dev/gpiochip0')
    gpio5 = gpio5_chip.get_line(5)
    gpio5.request(consumer='leds.py', type=gpiod.LINE_REQ_DIR_OUT, default_val=0)
    gpio5.set_value(1)
    return gpio5_chip, gpio5

def shutdown(chip, gpio):
    leds.close()
    gpio.set_value(0)
    chip.close()

def get_leds():
    # we have 12 LEDs on gpiochip0, connected to SPI0 MOSI (GPIO10) and CLK (GPIO11)
    pin_clk = 11
    pin_data = 10
    return apa102.APA102('/dev/gpiochip0', NLEDS, pin_clk, pin_data, True)

def add_color(a,b):
    return tuple(map(sum, zip(a,b)))

def show_time(leds, hours,minutes,seconds):
    global current_face
    led_hours = hours % NLEDS
    led_minutes = (minutes % 60) // (60 // NLEDS)
    led_seconds = (seconds % 60) // (60 // NLEDS)

    # correct for orientation
    correction_orientation = {'W':3, 'S':6, 'E':9}
    corr = correction_orientation[orientation]
    led_hours = (led_hours + corr) % NLEDS
    led_minutes = (led_minutes + corr) % NLEDS
    led_seconds = (led_seconds + corr) % NLEDS

    # progress hours hand on last 15 minutes of hour
    if minutes >= 45:
        led_hours = (led_hours +1) % NLEDS

    # progress minutess hand on second part of 5 minute interval
    if (minutes % 5) > 2:
        led_minutes = (led_minutes +1) % NLEDS

    colors = [(0,0,0)] * NLEDS
    colors[led_hours] = add_color(hour_color, colors[led_hours])
    colors[led_minutes] = add_color(minute_color, colors[led_minutes])
    
    # expand hours hand for progress during middle part of hour
    if minutes > 15 and minutes < 45:
        l = (led_hours +1) % NLEDS
        colors[l] = add_color(hour_color, colors[l])
    
    if SECONDS_HAND:
        # expand seconds hand to 4, one behind (because mod rounds down) and 2 in front
        for l in range(led_seconds -1, led_seconds +4):
            l %= NLEDS;
            colors[l] = add_color(second_color, colors[l])
    else:
        # show quarter ticks
        for tick in [0,3,6,9]:
            if colors[tick] == (0,0,0):
                colors[tick] = second_color

    if colors != current_face:
        for led in range(NLEDS):
            leds[led] = apa102.LedOutput(brightness, *colors[led])
        leds.commit()
        current_face = colors

def get_timeofday():
    now = localtime()
    return (now.tm_hour, now.tm_min, now.tm_sec)

def time_increment(hours,minutes,seconds):
    seconds = (seconds +1) % 60
    if seconds == 0:
        minutes = (minutes +1) % 60
        if minutes == 0:
            hours = (hours +1) % 24
    return (hours,minutes,seconds)


if __name__ == '__main__':
    gpio5_chip,gpio5 = poweron()
    leds = get_leds()

    (hours,minutes,seconds) = (0,0,0)
    while True:
        if UPDATE_INTERVAL > 1:
            show_time(leds, *get_timeofday())
        else:
            hours,minutes,seconds = time_increment(hours,minutes,seconds)
            show_time(leds, hours,minutes,seconds)
        sleep(UPDATE_INTERVAL)

    shutdown(gpio5_chip, gpio5) # never reached though..
