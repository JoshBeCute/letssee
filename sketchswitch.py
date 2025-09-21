#!/usr/bin/env python3
import curses
import os
import shutil
import subprocess
import json

PAYLOAD_DIR = os.path.expanduser('~/.Payloads')
FQBN_FILE = os.path.expanduser('~/.sketchswitch_fqbn_history.json')
PAYLOAD_CONTENT = """// Simple keyboard payload that types "easy easy lemon squeezy"
#include <Keyboard.h>
void setup() {
  Keyboard.begin();
  delay(3000);
  Keyboard.print("easy easy lemon squeezy");
  Keyboard.end();
}
void loop() {}
"""

def list_payloads():
    if not os.path.exists(PAYLOAD_DIR):
        return []
    return sorted([d for d in os.listdir(PAYLOAD_DIR) 
                  if os.path.isdir(os.path.join(PAYLOAD_DIR, d)) and 
                  any(f.endswith('.ino') for f in os.listdir(os.path.join(PAYLOAD_DIR, d)))])

def load_save_fqbn(save=None):
    if save:
        with open(FQBN_FILE, 'w') as f:
            json.dump(save[-20:], f)
    elif os.path.exists(FQBN_FILE):
        try:
            with open(FQBN_FILE, 'r') as f:
                return json.load(f)
        except: pass
    return []

def draw_box(s, title="", color=1):
    h, w = s.getmaxyx()
    s.attron(curses.color_pair(color))
    s.box()
    if title:
        s.addstr(0, max(0, (w - len(title)) // 2), title)
    s.attroff(curses.color_pair(color))

def center_text(s, y, text, color=0):
    _, w = s.getmaxyx()
    if color:
        s.attron(curses.color_pair(color))
    s.addstr(y, max(0, (w - len(text)) // 2), text[:w-1])
    if color:
        s.attroff(curses.color_pair(color))

def get_input(s, prompt, default="", hist=None):
    curses.curs_set(1)
    h, w = s.getmaxyx()
    text = default
    hist_idx = len(hist) if hist else 0
    
    while True:
        s.clear()
        draw_box(s, " Input ")
        s.addstr(1, 2, prompt + text)
        s.addstr(3, 2, "Enter: confirm | q: cancel")
        
        if hist:
            s.addstr(5, 2, "History:")
            for i, item in enumerate(hist[-5:]):
                prefix = "-> " if len(hist)-5+i == hist_idx else "   "
                s.addstr(6+i, 2, prefix + item[:w-6])
        
        s.move(1, 2 + len(prompt) + len(text))
        s.refresh()
        
        key = s.getch()
        if key in (10, 13):  # Enter
            curses.curs_set(0)
            return text.strip() if text.strip() else None
        elif key in (27, ord('q')):  # Escape or q
            curses.curs_set(0)
            return None
        elif key in (8, 127, curses.KEY_BACKSPACE):
            text = text[:-1]
        elif 32 <= key <= 126:
            text += chr(key)
        elif hist:
            if key == curses.KEY_UP and hist_idx > 0:
                hist_idx -= 1
                text = hist[hist_idx]
            elif key == curses.KEY_DOWN:
                if hist_idx < len(hist) - 1:
                    hist_idx += 1
                    text = hist[hist_idx]
                else:
                    hist_idx = len(hist)
                    text = default

def create_payload(s):
    os.makedirs(PAYLOAD_DIR, exist_ok=True)
    
    while True:
        s.clear()
        draw_box(s, " Create Payload ")
        center_text(s, 1, "Enter payload name (alphanumeric, q to cancel):", 3)
        s.refresh()
        
        curses.echo()
        name = curses.newwin(1, s.getmaxyx()[1]-4, 3, 2).getstr().decode('utf-8').strip()
        curses.noecho()
        curses.curs_set(0)
        
        if name.lower() == 'q':
            break
        
        if not name.isalnum():
            s.addstr(5, 2, "Invalid name! Use only alphanumeric characters.", curses.color_pair(3))
            s.addstr(6, 2, "Press any key to try again.")
            s.refresh()
            s.getch()
            continue
        
        folder = os.path.join(PAYLOAD_DIR, name)
        file = os.path.join(folder, f"{name}.ino")
        
        if os.path.exists(file):
            s.addstr(5, 2, f"Payload '{name}.ino' already exists.", curses.color_pair(3))
            s.addstr(6, 2, "Press any key to try again.")
            s.refresh()
            s.getch()
            continue
        
        os.makedirs(folder, exist_ok=True)
        with open(file, 'w') as f:
            f.write(PAYLOAD_CONTENT)
        
        s.addstr(5, 2, f"Payload '{name}.ino' created successfully.", curses.color_pair(2))
        s.addstr(6, 2, "Press any key to create another or q to quit.")
        s.refresh()
        
        if s.getch() == ord('q'):
            break

def run_cmd(s, action, cmd):
    h, w = s.getmaxyx()
    s.clear()
    draw_box(s, f" {action} ")
    s.addstr(1, 2, f"Command: {' '.join(cmd)}")
    s.addstr(3, 2, "Output:")
    s.refresh()
    
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    line = 4
    
    for output in proc.stdout:
        if line >= h - 2:
            s.scrl(1)
            line -= 1
        s.addstr(line, 2, output.strip()[:w-4])
        s.refresh()
        line += 1
    
    proc.wait()
    success = proc.returncode == 0
    s.addstr(h-2, 2, f"{action} {'succeeded' if success else 'failed'}! Press any key...")
    s.refresh()
    s.getch()
    return success

def handle_payload(s, folder, action):
    path = os.path.join(PAYLOAD_DIR, folder)
    ino_files = [f for f in os.listdir(path) if f.endswith('.ino')]
    
    if not ino_files:
        s.clear()
        s.addstr(0, 0, f"Error: No .ino file found for {action}!")
        s.addstr(1, 0, "Press any key to return...")
        s.refresh()
        s.getch()
        return
    
    ino = os.path.join(path, ino_files[0])
    
    if action == "edit":
        curses.endwin()
        try:
            subprocess.run(['nano', ino])
        except Exception as e:
            print(f"Error: {e}")
            input("Press Enter to continue...")
        return
    
    # Compile or Upload
    hist = load_save_fqbn()
    fqbn = get_input(s, "Enter FQBN: ", hist=hist)
    if not fqbn:
        return
    
    if fqbn not in hist:
        hist.append(fqbn)
        load_save_fqbn(hist)
    
    if action == "compile":
        run_cmd(s, "Compile", ["arduino-cli", "compile", "--fqbn", fqbn, ino])
    else:  # upload
        port = get_input(s, "Enter serial port: ", "/dev/ttyACM0")
        if not port:
            return
        
        if not run_cmd(s, "Upload", ["arduino-cli", "upload", "-p", port, "-b", fqbn, ino]):
            if port == '/dev/ttyACM0':
                s.addstr(0, 2, "Failed on ACM0, trying ACM1... Press any key.")
                s.refresh()
                s.getch()
                run_cmd(s, "Upload Retry", ["arduino-cli", "upload", "-p", '/dev/ttyACM1', "-b", fqbn, ino])

def main(s):
    curses.curs_set(0)
    curses.start_color()
    curses.use_default_colors()
    for i, fg, bg in [(1, curses.COLOR_CYAN, -1), (2, curses.COLOR_BLACK, curses.COLOR_WHITE), (3, curses.COLOR_YELLOW, -1)]:
        curses.init_pair(i, fg, bg)
    
    while True:
        folders = list_payloads()
        h, w = s.getmaxyx()
        s.clear()
        
        draw_box(s, " sketchswitch - Payload Selector ")
        inst = "↑/↓ or j/k Navigate | Enter Select | c Create | d Delete | e Edit | g Compile | u Upload | q Quit"
        center_text(s, 1, inst, 3)
        
        if not folders:
            center_text(s, h//2, "No payload folders with .ino files found in ~/.Payloads")
            s.refresh()
            key = s.getch()
            if key == ord('q'):
                return
            elif key == ord('c'):
                create_payload(s)
            continue
        
        sel = start = 0
        max_show = h - 5
        
        while True:
            s.clear()
            draw_box(s, " sketchswitch - Payload Selector ")
            center_text(s, 1, inst, 3)
            
            if sel >= start + max_show:
                start = sel - max_show + 1
            elif sel < start:
                start = sel
            
            for i, folder in enumerate(folders[start:start+max_show]):
                y = 3 + i
                if start + i == sel:
                    s.attron(curses.color_pair(2))
                    s.addstr(y, 2, folder[:w-4])
                    s.attroff(curses.color_pair(2))
                else:
                    s.addstr(y, 2, folder[:w-4])
            
            s.refresh()
            key = s.getch()
            
            if key == ord('q'):
                return
            elif key == ord('c'):
                create_payload(s)
                break
            elif key == ord('e') and folders:
                handle_payload(s, folders[sel], "edit")
                break
            elif key == ord('g') and folders:
                handle_payload(s, folders[sel], "compile")
                break
            elif key == ord('u') and folders:
                handle_payload(s, folders[sel], "upload")
                break
            elif key == ord('d') and folders:
                s.clear()
                s.addstr(0, 0, f"Delete '{folders[sel]}'?")
                s.addstr(1, 0, "Press Enter to confirm, any other key to cancel.")
                s.refresh()
                if s.getch() in (10, 13):
                    shutil.rmtree(os.path.join(PAYLOAD_DIR, folders[sel]))
                break
            elif key in (curses.KEY_UP, ord('k')):
                sel = (sel - 1) % len(folders)
            elif key in (curses.KEY_DOWN, ord('j')):
                sel = (sel + 1) % len(folders)
            elif key in (10, 13):
                s.addstr(h-2, 2, f"Selected: {folders[sel]}")
                s.refresh()
                s.getch()

if __name__ == "__main__":
    curses.wrapper(main)
