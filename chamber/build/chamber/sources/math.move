module chamber::math {
    /// Error codes
    const E_DIVIDE_BY_ZERO: u64 = 0;
    const E_MULTIPLICATION_OVERFLOW: u64 = 1;
    const E_ADDITION_OVERFLOW: u64 = 2;
    const E_SUBTRACTION_UNDERFLOW: u64 = 3;

    /// Basis points (1/10000)
    const BASIS_POINTS: u64 = 10000;

    /// Safe multiplication that checks for overflow
    public fun mul(x: u64, y: u64): u64 {
        let (result, overflow) = overflow_mul(x, y);
        assert!(!overflow, E_MULTIPLICATION_OVERFLOW);
        result
    }

    /// Safe division that checks for division by zero
    public fun div(x: u64, y: u64): u64 {
        assert!(y != 0, E_DIVIDE_BY_ZERO);
        x / y
    }

    /// Safe addition that checks for overflow
    public fun add(x: u64, y: u64): u64 {
        let (result, overflow) = overflow_add(x, y);
        assert!(!overflow, E_ADDITION_OVERFLOW);
        result
    }

    /// Safe subtraction that checks for underflow
    public fun sub(x: u64, y: u64): u64 {
        assert!(x >= y, E_SUBTRACTION_UNDERFLOW);
        x - y
    }

    /// Multiply basis points (used for fees, rates)
    public fun mul_bps(x: u64, bps: u64): u64 {
        div(mul(x, bps), BASIS_POINTS)
    }

    /// Multiply and divide with same denominator avoiding overflow
    public fun mul_div(x: u64, y: u64, z: u64): u64 {
        assert!(z != 0, E_DIVIDE_BY_ZERO);
        // Multiply in u128 to avoid overflow
        let result = (((x as u128) * (y as u128)) / (z as u128));
        // Convert back to u64
        (result as u64)
    }

    /// Checks if multiplication would overflow
    fun overflow_mul(x: u64, y: u64): (u64, bool) {
        let result = (x as u128) * (y as u128);
        if (result > 18446744073709551615) { // 2^64 - 1
            (0, true)
        } else {
            ((result as u64), false)
        }
    }

    /// Checks if addition would overflow
    fun overflow_add(x: u64, y: u64): (u64, bool) {
        if (x > 18446744073709551615 - y) { // 2^64 - 1
            (0, true)
        } else {
            (x + y, false)
        }
    }

    /// Returns minimum of two numbers
    public fun min(x: u64, y: u64): u64 {
        if (x < y) x else y
    }

    /// Returns maximum of two numbers
    public fun max(x: u64, y: u64): u64 {
        if (x > y) x else y
    }
}