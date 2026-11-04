pub fn add(a: i64, b: i64) -> i64 {
    a + b
}

pub fn subtract(a: i64, b: i64) -> i64 {
    a - b
}

pub fn multiply(a: i64, b: i64) -> i64 {
    a * b
}

pub fn divide(a: i64, b: i64) -> Result<i64, &'static str> {
    if b == 0 {
        return Err("Cannot divide by zero");
    }
    Ok(a / b)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adds() {
        assert_eq!(add(1, 2), 3);
    }

    #[test]
    fn subtracts() {
        assert_eq!(subtract(5, 2), 3);
    }

    #[test]
    fn multiplies() {
        assert_eq!(multiply(3, 4), 12);
    }

    #[test]
    fn divides() {
        assert_eq!(divide(10, 2), Ok(5));
    }

    #[test]
    fn divide_by_zero_is_an_error() {
        assert_eq!(divide(10, 0), Err("Cannot divide by zero"));
    }
}
