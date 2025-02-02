// validation.move
module chamber::validation {
   use chamber::config::{Self, Config}; 
   use chamber::treasury::{Self, Treasury};
   use chamber::exchange::{Self, ExchangeRate};

   // Error codes
   const E_INVALID_AMOUNT: u64 = 0;
   const E_BELOW_MINIMUM: u64 = 1;
   const E_ABOVE_MAXIMUM: u64 = 2;  
   const E_UNAUTHORIZED: u64 = 4;
   const E_SYSTEM_PAUSED: u64 = 5;
   const E_SUPPLY_MISMATCH: u64 = 6;
   const E_INVALID_VALIDATOR: u64 = 7;
   const E_CAPACITY_EXCEEDED: u64 = 8;

   // System constants
   const MIN_STAKE_AMOUNT: u64 = 1_000_000;
   const MAX_STAKE_AMOUNT: u64 = 10_000_000_000_000;
   const SYSTEM_CAPACITY: u64 = 100_000_000_000_000;

   public fun validate_system_state(config: &Config) {
       assert!(!config::is_paused(config), E_SYSTEM_PAUSED);
       assert!(config::get_total_staked(config) <= SYSTEM_CAPACITY, E_CAPACITY_EXCEEDED);
   }

   public fun validate_balances(treasury: &Treasury, exchange: &ExchangeRate) {
       assert!(
           treasury::get_stake_balance(treasury) == exchange::get_total_sui(exchange),
           E_SUPPLY_MISMATCH
       );
   }

   public fun validate_validator(config: &Config, validator_addr: address) {
       assert!(config::is_validator_active(config, validator_addr, 0), E_INVALID_VALIDATOR);
   }

   public fun validate_stake_amount(amount: u64) {
       assert!(amount > 0, E_INVALID_AMOUNT);
       assert!(amount >= MIN_STAKE_AMOUNT, E_BELOW_MINIMUM);
       assert!(amount <= MAX_STAKE_AMOUNT, E_ABOVE_MAXIMUM);
   }

   public fun validate_withdraw_amount(stake_amount: u64, withdraw_amount: u64) {
       assert!(withdraw_amount > 0, E_INVALID_AMOUNT);
       assert!(withdraw_amount <= stake_amount, E_INVALID_AMOUNT);
   }

   public fun validate_owner(owner_id: ID, ctx: &TxContext) {
       assert!(
           object::id_from_address(sui::tx_context::sender(ctx)) == owner_id,
           E_UNAUTHORIZED
       );
   }

   public fun validate_stake_for_system(config: &Config, amount: u64) {
        let total_staked = config::get_total_staked(config);
        let potential_total = total_staked + amount;

        // Capacity check
        if (potential_total > SYSTEM_CAPACITY) {
            abort E_CAPACITY_EXCEEDED
        };

        // Basic validations
        assert!(amount > 0, E_INVALID_AMOUNT);
        assert!(amount >= MIN_STAKE_AMOUNT, E_BELOW_MINIMUM);

        // Maximum stake amount check MUST be last
        //assert!(amount <= MAX_STAKE_AMOUNT, E_ABOVE_MAXIMUM);
    }

   public fun validate_percentage(value: u64) {
       assert!(value <= 100, E_INVALID_AMOUNT);
   }

   public fun validate_basis_points(value: u64) {
       assert!(value <= 10000, E_INVALID_AMOUNT);
   }

   #[test_only]
   public fun get_min_stake(): u64 { MIN_STAKE_AMOUNT }

   #[test_only]
   public fun get_max_stake(): u64 { MAX_STAKE_AMOUNT }
}
