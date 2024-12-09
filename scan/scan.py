import os
import sys


def scan_folder(folder_path):
    if not os.path.exists(folder_path):
        print(f"Error: Folder '{folder_path}' does not exist.")
        sys.exit(1)

    print(f"Scanning folder: {folder_path}")
    for root, dirs, files in os.walk(folder_path):
        for file in files:
            print(f"Found file: {os.path.join(root, file)}")


def main():
    folder = os.getenv("INPUT_FOLDER")  # GitHub Actions provides inputs as environment variables
    if not folder:
        print("Error: 'folder' input is required")
        sys.exit(1)
    scan_folder(folder)
    return "Success"
