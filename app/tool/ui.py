"""Tiny adb UI driver: python3 ui.py tap "Email"  |  python3 ui.py dump"""
import re, subprocess, sys, time

def dump():
    subprocess.run(["adb", "shell", "uiautomator", "dump", "/sdcard/u.xml"], capture_output=True)
    return subprocess.run(["adb", "shell", "cat", "/sdcard/u.xml"], capture_output=True, text=True).stdout

def find(label, xml):
    for m in re.finditer(r"<node [^>]*>", xml):
        n = m.group(0)
        attrs = " ".join(re.findall(r'(?:text|content-desc|hint)="([^"]*)"', n))
        if label.lower() in attrs.lower():
            b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
            if b:
                x1, y1, x2, y2 = map(int, b.groups())
                return (x1 + x2) // 2, (y1 + y2) // 2
    return None

cmd = sys.argv[1]
if cmd == "dump":
    xml = dump()
    print("\n".join(sorted(set(a for a in re.findall(r'(?:text|content-desc|hint)="([^"]+)"', xml)))))
elif cmd == "tap":
    for _ in range(10):
        p = find(sys.argv[2], dump())
        if p:
            subprocess.run(["adb", "shell", "input", "tap", str(p[0]), str(p[1])])
            print("tapped", sys.argv[2], p); break
        time.sleep(2)
    else:
        print("NOT FOUND", sys.argv[2])
