# Simple Math Project

This project implements basic mathematical operations including addition, subtraction, multiplication, and division. It also includes unit tests to verify the correctness of these operations.

## Project Structure

```
javascript_simple_math
├── src
│   └── index.js          # Implementation of simple math functions
├── test
│   └── simpleMath.test.js # Unit tests for the math functions
├── package.json          # Project metadata and dependencies
├── yarn.lock             # Resolved dependency versions
└── README.md             # Project documentation
```

## Dependencies

The one dependency, `@ossprey/test-package`, is a benign package we publish and
the Ossprey API deliberately flags as malicious. It exists so a scan of this
fixture has something to catalogue, and so a live scan reaches a real malware
verdict. It is not used by the code below.

## Installation

To get started, clone the repository and navigate to the project directory:

```bash
git clone <repository-url>
cd javascript_simple_math
```

Then, install the necessary dependencies:

```bash
yarn install
```

## Running Tests

To run the unit tests, use the following command:

```bash
yarn test
```

This will execute the tests defined in `test/simpleMath.test.js` and display the results in the console.

## Usage

You can import the math functions from `src/index.js` in your JavaScript files as follows:

```javascript
const { add, subtract, multiply, divide } = require('./src/index');
```

Then, you can use these functions to perform simple math operations.