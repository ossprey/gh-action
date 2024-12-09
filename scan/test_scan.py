import os
from scan.scan import main


def test_main_function():
    # Add INPUT_FOLDER to environment variables
    os.environ["INPUT_FOLDER"] = "test/simple_math"
    assert main() == "Success"
