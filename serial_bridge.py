#!/usr/bin/env python3
"""
NEON INFINITY DUO - serial <-> UDP bridge
=========================================
Godot cannot read USB-serial ports by itself, so this tiny program sits in the middle:

    ESP32 board(s) --USB serial--> this bridge --UDP 127.0.0.1:4210--> Godot   (joystick + buttons)
    ESP32 board 1  <--USB serial-- this bridge <--UDP 127.0.0.1:4211-- Godot   (buzzer + LED events)

Usage
    pip install pyserial
    python serial_bridge.py                       # auto-detects every ESP32 plugged in
    python serial_bridge.py --ports COM5 COM6     # or name the ports yourself (Windows)
    python serial_bridge.py --ports /dev/ttyUSB0 /dev/ttyUSB1      # Linux
    python serial_bridge.py --list                # just show the serial ports and quit

You do not have to say which board is player 1 - every line starts with the player id.
Leave this window open while you play. Ctrl+C stops it.
"""
import argparse
import socket
import sys
import threading
import time

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    sys.exit("pyserial is missing.  Install it with:   pip install pyserial")

GODOT_ADDR = ("127.0.0.1", 4210)     # Godot listens here for joystick data
EVENT_PORT = 4211                    # Godot sends game events here

# USB chips found on ESP32 DevKit V1 boards (CP210x, CH340/CH341, FTDI, native USB)
KNOWN_VIDS = {0x10C4, 0x1A86, 0x0403, 0x303A}

out_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
boards = {}                 # player id (int) -> serial.Serial   (learned from incoming lines)
boards_lock = threading.Lock()
stop = threading.Event()


def find_ports():
    found = []
    for p in list_ports.comports():
        if p.vid in KNOWN_VIDS:
            found.append(p.device)
    return found


def valid_line(line):
    """id,x,y,jump,stop,pause,start  (7 fields) - ignore boot messages and garbage."""
    parts = line.split(",")
    if len(parts) != 7:
        return None
    try:
        pid = int(parts[0])
        [float(v) for v in parts[1:3]]
        [int(v) for v in parts[3:]]
    except ValueError:
        return None
    return pid if pid in (1, 2) else None


def reader(ser, name):
    """Forward every valid joystick line from one board to Godot."""
    buf = b""
    announced = False
    while not stop.is_set():
        try:
            chunk = ser.read(ser.in_waiting or 1)
        except (serial.SerialException, OSError):
            print(f"[{name}] disconnected. Unplug/replug it and restart the bridge.")
            return
        if not chunk:
            continue
        buf += chunk
        while b"\n" in buf:
            raw, buf = buf.split(b"\n", 1)
            line = raw.decode("utf-8", errors="ignore").strip()
            pid = valid_line(line)
            if pid is None:
                continue
            if not announced:
                announced = True
                print(f"[{name}] is player {pid}")
            with boards_lock:
                boards[pid] = ser
            out_sock.sendto(line.encode(), GODOT_ADDR)


def event_listener():
    """Game events (E,stone ...) go to player 1's board, which owns the buzzer."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", EVENT_PORT))
    sock.settimeout(0.3)
    while not stop.is_set():
        try:
            data, _ = sock.recvfrom(256)
        except socket.timeout:
            continue
        with boards_lock:
            target = boards.get(1)
        if target is None:
            continue
        try:
            target.write(data if data.endswith(b"\n") else data + b"\n")
        except (serial.SerialException, OSError):
            pass


def main():
    ap = argparse.ArgumentParser(description="Bridge ESP32 joysticks to the Godot game")
    ap.add_argument("--ports", nargs="*", help="serial ports, e.g. COM5 COM6 (default: auto-detect)")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--list", action="store_true", help="list serial ports and exit")
    args = ap.parse_args()

    if args.list:
        for p in list_ports.comports():
            print(f"{p.device:15} {p.description}")
        return

    ports = args.ports or find_ports()
    if not ports:
        print("No ESP32 boards found. Plug them in, or use:  --ports COM5 COM6")
        print("Visible serial ports:")
        for p in list_ports.comports():
            print(f"   {p.device:15} {p.description}")
        sys.exit(1)

    threads = []
    for port in ports:
        try:
            ser = serial.Serial(port, args.baud, timeout=0.1)
        except serial.SerialException as e:
            print(f"Could not open {port}: {e}")
            continue
        print(f"Opened {port}")
        t = threading.Thread(target=reader, args=(ser, port), daemon=True)
        t.start()
        threads.append(t)
    if not threads:
        sys.exit(1)

    threading.Thread(target=event_listener, daemon=True).start()
    print("Bridge running.  Start the game now.  (Ctrl+C to stop)")
    try:
        while any(t.is_alive() for t in threads):
            time.sleep(0.5)
    except KeyboardInterrupt:
        pass
    stop.set()


if __name__ == "__main__":
    main()
