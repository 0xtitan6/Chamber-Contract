module chamber::exchange {
    use sui::event;
    use chamber::math;

    /// Error codes
    const E_RATE_TOO_LOW: u64 = 1;
    const E_RATE_TOO_HIGH: u64 = 2;

    /// Precision for rate calculations (9 decimals)
    const RATE_PRECISION: u64 = 1_000_000_000;
    /// Minimum rate (0.1 cSUI per SUI)
    const MIN_RATE: u64 = 100_000_000;
    /// Maximum rate (10 cSUI per SUI)
    const MAX_RATE: u64 = 10_000_000_000;

    /// Exchange rate data
    public struct ExchangeRate has key {
        id: UID,
        /// Current rate between cSUI and SUI
        rate: u64,
        /// Total SUI staked
        total_sui: u64,
        /// Total cSUI supply
        total_csui: u64,
        /// Last update timestamp
        last_update: u64
    }

    /// Events
    public struct RateUpdated has copy, drop {
        old_rate: u64,
        new_rate: u64,
        total_sui: u64,
        total_csui: u64,
        timestamp: u64
    }

    /// Initialize exchange rate
    fun init(ctx: &mut TxContext) {
        let exchange_rate = ExchangeRate {
            id: object::new(ctx),
            rate: RATE_PRECISION,  // Initial 1:1 rate
            total_sui: 0,
            total_csui: 0,
            last_update: tx_context::epoch(ctx)
        };

        transfer::share_object(exchange_rate);
    }

    /// Convert SUI amount to cSUI amount
    public fun sui_to_csui(rate: &ExchangeRate, sui_amount: u64): u64 {
        math::mul_div(sui_amount, RATE_PRECISION, rate.rate)
    }

    /// Convert cSUI amount to SUI amount
    public fun csui_to_sui(rate: &ExchangeRate, csui_amount: u64): u64 {
        math::mul_div(csui_amount, rate.rate, RATE_PRECISION)
    }

    /// Update exchange rate based on new stake amount
    public fun update_rate_stake(
        rate: &mut ExchangeRate,
        sui_amount: u64,
        ctx: &mut TxContext
    ) {
        let old_rate = rate.rate;
        
        // Update totals
        rate.total_sui = math::add(rate.total_sui, sui_amount);
        // Calculate new cSUI amount at current rate
        let csui_amount = sui_to_csui(rate, sui_amount);
        rate.total_csui = math::add(rate.total_csui, csui_amount);

        // Calculate new rate
        if (rate.total_csui == 0) {
            rate.rate = RATE_PRECISION;
        } else {
            rate.rate = math::mul_div(rate.total_sui, RATE_PRECISION, rate.total_csui);
        };

        // Validate rate bounds
        assert!(rate.rate >= MIN_RATE, E_RATE_TOO_LOW);
        assert!(rate.rate <= MAX_RATE, E_RATE_TOO_HIGH);

        rate.last_update = tx_context::epoch(ctx);

        event::emit(RateUpdated {
            old_rate,
            new_rate: rate.rate,
            total_sui: rate.total_sui,
            total_csui: rate.total_csui,
            timestamp: rate.last_update
        });
    }

    /// Update exchange rate based on unstake amount
    public fun update_rate_unstake(
        rate: &mut ExchangeRate,
        sui_amount: u64,
        ctx: &mut TxContext
    ) {
        let old_rate = rate.rate;

        // Update totals
        rate.total_sui = math::sub(rate.total_sui, sui_amount);
        // Calculate cSUI amount at current rate
        let csui_amount = sui_to_csui(rate, sui_amount);
        rate.total_csui = math::sub(rate.total_csui, csui_amount);

        // Calculate new rate
        if (rate.total_csui == 0) {
            rate.rate = RATE_PRECISION;
        } else {
            rate.rate = math::mul_div(rate.total_sui, RATE_PRECISION, rate.total_csui);
        };

        // Validate rate bounds
        assert!(rate.rate >= MIN_RATE, E_RATE_TOO_LOW);
        assert!(rate.rate <= MAX_RATE, E_RATE_TOO_HIGH);

        rate.last_update = tx_context::epoch(ctx);

        event::emit(RateUpdated {
            old_rate,
            new_rate: rate.rate,
            total_sui: rate.total_sui,
            total_csui: rate.total_csui,
            timestamp: rate.last_update
        });
    }

    public fun update_rate_rewards(
        rate: &mut ExchangeRate,
        reward_amount: u64,
        ctx: &mut TxContext
    ) {
        let old_rate = rate.rate;
        
        // For rewards, only total_sui increases while total_csui stays the same
        rate.total_sui = math::add(rate.total_sui, reward_amount);

        // Calculate new rate
        if (rate.total_csui == 0) {
            rate.rate = RATE_PRECISION;
        } else {
            rate.rate = math::mul_div(rate.total_sui, RATE_PRECISION, rate.total_csui);
        };

        // Validate rate bounds
        assert!(rate.rate >= MIN_RATE, E_RATE_TOO_LOW);
        assert!(rate.rate <= MAX_RATE, E_RATE_TOO_HIGH);

        rate.last_update = tx_context::epoch(ctx);

        event::emit(RateUpdated {
            old_rate,
            new_rate: rate.rate,
            total_sui: rate.total_sui,
            total_csui: rate.total_csui,
            timestamp: rate.last_update
        });
    }

    /// Get current exchange rate
    public fun get_rate(rate: &ExchangeRate): u64 {
        rate.rate
    }

    /// Get total SUI staked
    public fun get_total_sui(rate: &ExchangeRate): u64 {
        rate.total_sui
    }

    /// Get total cSUI supply
    public fun get_total_csui(rate: &ExchangeRate): u64 {
        rate.total_csui
    }

    /// Get last update timestamp
    public fun get_last_update(rate: &ExchangeRate): u64 {
        rate.last_update
    }

    /// Get rate precision
    public fun get_rate_precision(): u64 {
        RATE_PRECISION
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }

    #[test_only]
    public fun get_min_rate(): u64 { MIN_RATE }
    
    #[test_only]
    public fun get_max_rate(): u64 { MAX_RATE }
}