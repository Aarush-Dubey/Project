
import sys
import os
import pyautogui

def capture_screenshot(output_path):
    """
    Capture a screenshot using pyautogui and save to fixed file.
    """
    try:
        screenshot = pyautogui.screenshot()
        screenshot.save(output_path)
        print(f"Screenshot saved to: {output_path}")
        return True
    except Exception as e:
        print(f"Failed to capture screenshot: {e}")
        return False

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 capture_screen.py <output_path>")
        sys.exit(1)

    output_path = sys.argv[1]
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    if capture_screenshot(output_path):
        print("Screenshot capture completed successfully")
        sys.exit(0)
    else:
        print("Screenshot capture failed")
        sys.exit(1)

if __name__ == "__main__":
    main()
