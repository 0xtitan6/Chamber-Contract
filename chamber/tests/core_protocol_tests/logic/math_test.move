#[test_only]
module chamber::math_tests {
    use chamber::math;

    const MAX_U64: u64 = 18446744073709551615;

    #[test]
    fun test_basic_operations() {
        // Test multiplication
        assert!(math::mul(2, 3) == 6, 0);
        assert!(math::mul(0, 5) == 0, 1);
        assert!(math::mul(5, 0) == 0, 2);
        
        // Test division
        assert!(math::div(6, 2) == 3, 3);
        assert!(math::div(5, 2) == 2, 4); // Integer division
        assert!(math::div(0, 5) == 0, 5);
        
        // Test addition
        assert!(math::add(2, 3) == 5, 6);
        assert!(math::add(0, 5) == 5, 7);
        assert!(math::add(5, 0) == 5, 8);
        
        // Test subtraction
        assert!(math::sub(5, 3) == 2, 9);
        assert!(math::sub(5, 0) == 5, 10);
        assert!(math::sub(5, 5) == 0, 11);
    }

    #[test]
    fun test_basis_points() {
        // 100% = 10000 basis points
        assert!(math::mul_bps(1000, 10000) == 1000, 0);
        // 50% = 5000 basis points
        assert!(math::mul_bps(1000, 5000) == 500, 1);
        // 5% = 500 basis points
        assert!(math::mul_bps(1000, 500) == 50, 2);
        // 0% = 0 basis points
        assert!(math::mul_bps(1000, 0) == 0, 3);
    }

    #[test]
    fun test_mul_div() {
        assert!(math::mul_div(100, 200, 50) == 400, 0);
        assert!(math::mul_div(0, 200, 50) == 0, 1);
        assert!(math::mul_div(100, 0, 50) == 0, 2);
        assert!(math::mul_div(MAX_U64, 1, MAX_U64) == 1, 3); // Should not overflow
    }

    #[test]
    fun test_min_max() {
        assert!(math::min(5, 3) == 3, 0);
        assert!(math::min(3, 5) == 3, 1);
        assert!(math::min(5, 5) == 5, 2);
        
        assert!(math::max(5, 3) == 5, 3);
        assert!(math::max(3, 5) == 5, 4);
        assert!(math::max(5, 5) == 5, 5);
    }

    #[test]
    fun test_edge_cases() {
        // Test with 0
        assert!(math::mul_div(0, 0, 1) == 0, 0);
        assert!(math::mul_bps(0, 5000) == 0, 1);
        assert!(math::min(0, 0) == 0, 2);
        assert!(math::max(0, 0) == 0, 3);
    }

    #[test]
    #[expected_failure(abort_code = math::E_DIVIDE_BY_ZERO)]
    fun test_div_by_zero() {
        math::div(1, 0);
    }

    #[test]
    #[expected_failure(abort_code = math::E_MULTIPLICATION_OVERFLOW)]
    fun test_mul_overflow() {
        math::mul(MAX_U64, 2);
    }

    #[test]
    #[expected_failure(abort_code = math::E_SUBTRACTION_UNDERFLOW)]
    fun test_sub_underflow() {
        math::sub(1, 2);
    }

    #[test]
    #[expected_failure(abort_code = math::E_ADDITION_OVERFLOW)]
    fun test_add_overflow() {
        math::add(MAX_U64, 1);
    }
}