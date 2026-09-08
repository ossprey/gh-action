# setup.py

from setuptools import setup, find_packages

setup(
    name="simple_math",
    version="0.1.0",
    packages=find_packages(),
    install_requires=[
        "requests==2.34.2"
    ],
    entry_points={
        'console_scripts': [
            'simple-math=simple_math.operations:add',
        ],
    },
)
