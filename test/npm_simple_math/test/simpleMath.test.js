// node:test, not jest: the fixture needs a dependency set the scanner can
// catalogue, not a test runner's worth of transitive packages sitting in the
// lockfile collecting CVE alerts. Run with `npm test`.
const test = require('node:test');
const assert = require('node:assert');

const { add, subtract, multiply, divide } = require('../src/index');

test('adds 1 + 2 to equal 3', () => {
    assert.strictEqual(add(1, 2), 3);
});

test('subtracts 5 - 2 to equal 3', () => {
    assert.strictEqual(subtract(5, 2), 3);
});

test('multiplies 3 * 4 to equal 12', () => {
    assert.strictEqual(multiply(3, 4), 12);
});

test('divides 10 / 2 to equal 5', () => {
    assert.strictEqual(divide(10, 2), 5);
});

test('divides by zero should throw', () => {
    assert.throws(() => divide(10, 0), /Cannot divide by zero/);
});
