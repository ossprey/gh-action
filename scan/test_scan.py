import os
from scan.scan import main


def test_main_function():
    os.environ["INPUT_FOLDER"] = "test/simple_math"
    ret = main()
    del os.environ["INPUT_FOLDER"]

    assert ret == "Success"
