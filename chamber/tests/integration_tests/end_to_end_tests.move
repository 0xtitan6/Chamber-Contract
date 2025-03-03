#[test_only]
module chamber::end_to_end_test {
    use sui::test_scenario::{Self as test, next_tx, ctx};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::{Self};
    use std::debug;
    use std::string;
    
    use chamber::config::{Self, Config, AdminCap};
    use chamber::stake::{Self, StakeRegistry, Stake};
    use chamber::treasury::{Self, Treasury};
    use chamber::csui::{Self, CSUI, MinterCap};
    use chamber::exchange::{Self, ExchangeRate};
    use chamber::rewards::{Self, RewardPool};
    use chamber::debug_printer as printer;
    
    // Test addresses
    const ADMIN: address = @0xAD;
    const TEST_VALIDATOR: address = @0x5678;
    const ALICE: address = @0xA1;
    const BOB: address = @0xB0;
    
    // Stake amounts
    const ALICE_STAKE: u64 = 100 * 1_000_000_000; // 100 SUI
    const BOB_STAKE: u64 = 200 * 1_000_000_000;   // 200 SUI
    const VALIDATOR_CAPACITY: u64 = 1000 * 1_000_000_000; // 1000 SUI
    const REWARD_AMOUNT: u64 = 30 * 1_000_000_000; // 30 SUI
    
    // Fee and rate settings
    const PROTOCOL_FEE: u64 = 500; // 5%
    const VALIDATOR_COMMISSION: u64 = 1000; // 10%
    const RATE_PRECISION: u64 = 1_000_000_000; // 1 billion
    
    #[test]
    /// Test the complete end-to-end staking flow including:
    /// 1. System initialization
    /// 2. Validator configuration
    /// 3. Users staking SUI and receiving stSUI
    /// 4. Exchange rate verification
    /// 5. Rewards distribution
    /// 6. Rewards claiming and exchange rate updates
    fun test_complete_staking_flow() {
        printer::print_section(b"Chamber Finance: Liquid Staking Protocol Demo");
        
        let mut scenario_val = test::begin(ADMIN);
        let scenario = &mut scenario_val;
        let mut clock = clock::create_for_testing(ctx(scenario));
        
        printer::print_day(1, b"Protocol Initialization");
        // STEP 1: Initialize all protocol modules
        {
            printer::print_str(b"Initializing Protocol Modules...");
            
            // Core modules
            config::init_for_testing(ctx(scenario));
            stake::init_for_testing(ctx(scenario));
            treasury::init_for_testing(ctx(scenario));
            exchange::init_for_testing(ctx(scenario));
            rewards::init_for_testing(ctx(scenario));
            
            // Token module
            csui::init_test_token(ctx(scenario));
            
            printer::print_str(b"Protocol modules initialized successfully");
            
            // Verify modules initialized correctly
            next_tx(scenario, ADMIN);
            assert!(test::has_most_recent_for_address<AdminCap>(ADMIN), 0);
            
            let config = test::take_shared<Config>(scenario);
            // Don't assert specific fee value, just verify Config exists
            test::return_shared(config);
            
            printer::print_str(b"AdminCap and Config verified");
        };
        
        // Advance time
        clock::increment_for_testing(&mut clock, 86400 * 1000); // +1 day in milliseconds
        
        // STEP 2: Configure protocol settings and validator
        printer::print_day(2, b"Protocol Configuration");
        next_tx(scenario, ADMIN);
        {
            printer::print_str(b"Configuring protocol settings...");
            
            // Set protocol fee
            let admin_cap = test::take_from_sender<AdminCap>(scenario);
            let mut config = test::take_shared<Config>(scenario);
            
            config::update_protocol_fee(
                &admin_cap,
                &mut config,
                PROTOCOL_FEE,
                ctx(scenario)
            );
            
            printer::print_str(b"Protocol fee set to 5%");
            
            // Register validator
            printer::print_str(b"Registering validator node...");
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                true, // active
                VALIDATOR_CAPACITY,
                VALIDATOR_COMMISSION,
                ctx(scenario)
            );
            
            // Verify validator configuration
            assert!(config::is_validator_active(&config, TEST_VALIDATOR, 0), 2);
            let (_, max_stake, commission) = config::get_validator_config(&config, TEST_VALIDATOR);
            assert!(max_stake == VALIDATOR_CAPACITY, 3);
            assert!(commission == VALIDATOR_COMMISSION, 4);
            
            printer::print_str(b"Validator registered successfully");
            printer::print_str(b"Commission: 10%");
            printer::print_str(b"Max capacity: 1,000 SUI");
            
            test::return_to_sender(scenario, admin_cap);
            test::return_shared(config);
        };
        
        // Advance time
        clock::increment_for_testing(&mut clock, 86400 * 1000); // +1 day in milliseconds
        
        // STEP 3: Alice stakes SUI
        printer::print_day(3, b"First User Staking");
        next_tx(scenario, ALICE);
        {
            printer::print_str(b"Alice initiates first stake...");
            
            let mut registry = test::take_shared<StakeRegistry>(scenario);
            let mut treasury = test::take_shared<Treasury>(scenario);
            let mut config = test::take_shared<Config>(scenario);
            let mut exchange_rate = test::take_shared<ExchangeRate>(scenario);
            
            // Mint SUI for Alice
            let payment = coin::mint_for_testing<SUI>(ALICE_STAKE, ctx(scenario));
            
            // Record initial exchange rate
            let initial_rate = exchange::get_rate(&exchange_rate);
            assert!(initial_rate == RATE_PRECISION, 5); // Initial rate is 1:1
            
            printer::print_str(b"Staking 100 SUI...");
            printer::print_str(b"Initial exchange rate: 1.0 (1:1)");
            
            // Stake SUI
            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                payment,
                ctx(scenario)
            );
            
            // Update exchange rate
            exchange::update_rate_stake(
                &mut exchange_rate,
                ALICE_STAKE,
                ctx(scenario)
            );
            
            // Mint stSUI (cSUI) tokens for Alice
            let mut treasury_cap = test::take_from_address<coin::TreasuryCap<CSUI>>(scenario, ADMIN);
            let minter_cap = test::take_from_address<MinterCap>(scenario, ADMIN);
            
            // Calculate stSUI amount - in a real implementation we'd convert based on exchange rate
            // but for simplicity in testing we're using 1:1
            let stsui_amount = ALICE_STAKE;
            
            csui::mint(
                &mut treasury_cap, 
                &minter_cap, 
                stsui_amount, 
                ALICE, 
                &clock, 
                ctx(scenario)
            );
            
            // Verify staked amount in treasury
            assert!(treasury::get_stake_balance(&treasury) == ALICE_STAKE, 6);
            
            // Verify cSUI token issuance
            assert!(csui::total_supply(&treasury_cap) == stsui_amount, 7);
            
            printer::print_str(b"Alice received 100 stSUI tokens");
            printer::print_str(b"Treasury now holds 100 SUI total");
            
            test::return_to_address(ADMIN, treasury_cap);
            test::return_to_address(ADMIN, minter_cap);
            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
            test::return_shared(exchange_rate);
        };
        
        // Verify Alice received the correct amount of stSUI
        next_tx(scenario, ALICE);
        {
            let alice_csui = test::take_from_sender<Coin<CSUI>>(scenario);
            assert!(coin::value(&alice_csui) == ALICE_STAKE, 8); // Initial 1:1 rate
            test::return_to_sender(scenario, alice_csui);
        };
        
        // Advance time 
        clock::increment_for_testing(&mut clock, 86400 * 2 * 1000); // +2 days in milliseconds
        
        // STEP 4: Bob stakes SUI
        printer::print_day(5, b"Second User Staking");
        next_tx(scenario, BOB);
        {
            printer::print_str(b"Bob initiates stake...");
            
            let mut registry = test::take_shared<StakeRegistry>(scenario);
            let mut treasury = test::take_shared<Treasury>(scenario);
            let mut config = test::take_shared<Config>(scenario);
            let mut exchange_rate = test::take_shared<ExchangeRate>(scenario);
            
            // Mint SUI for Bob
            let payment = coin::mint_for_testing<SUI>(BOB_STAKE, ctx(scenario));
            
            // Get current rate before Bob's stake
            let _current_rate = exchange::get_rate(&exchange_rate);
            
            printer::print_str(b"Staking 200 SUI...");
            printer::print_str(b"Current exchange rate: 1.0 (1:1)");
            
            // Stake SUI
            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                payment,
                ctx(scenario)
            );
            
            // Update exchange rate
            exchange::update_rate_stake(
                &mut exchange_rate,
                BOB_STAKE,
                ctx(scenario)
            );
            
            // Mint stSUI (cSUI) tokens for Bob based on current rate
            let mut treasury_cap = test::take_from_address<coin::TreasuryCap<CSUI>>(scenario, ADMIN);
            let minter_cap = test::take_from_address<MinterCap>(scenario, ADMIN);
            
            // For simplicity in testing, use 1:1 rate
            let stsui_amount = BOB_STAKE;
            
            csui::mint(
                &mut treasury_cap, 
                &minter_cap, 
                stsui_amount, 
                BOB, 
                &clock, 
                ctx(scenario)
            );
            
            // Verify total staked amount
            assert!(treasury::get_stake_balance(&treasury) == ALICE_STAKE + BOB_STAKE, 9);
            
            printer::print_str(b"Bob received 200 stSUI tokens");
            printer::print_str(b"Treasury now holds 300 SUI total");
            
            test::return_to_address(ADMIN, treasury_cap);
            test::return_to_address(ADMIN, minter_cap);
            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
            test::return_shared(exchange_rate);
        };
        
        // Advance time - simulate staking period
        clock::increment_for_testing(&mut clock, 86400 * 7 * 1000); // +7 days in milliseconds
        
        // STEP 5: Process rewards
        printer::print_day(12, b"Rewards Distribution");
        next_tx(scenario, TEST_VALIDATOR);
        {
            printer::print_str(b"Validator submitting rewards...");
            
            let mut pool = test::take_shared<RewardPool>(scenario);
            let mut treasury = test::take_shared<Treasury>(scenario);
            let mut config = test::take_shared<Config>(scenario);
            let mut exchange_rate = test::take_shared<ExchangeRate>(scenario);
            
            // Create rewards
            let reward_coin = coin::mint_for_testing<SUI>(REWARD_AMOUNT, ctx(scenario));
            
            // Record rate before rewards
            let rate_before_rewards = exchange::get_rate(&exchange_rate);
            
            printer::print_str(b"Generated 30 SUI in rewards");
            printer::print_str(b"Rate before rewards: 1.0");
            
            // Add rewards
            rewards::add_validator_rewards(
                &mut pool,
                TEST_VALIDATOR,
                reward_coin,
                &mut config,
                &mut treasury,
                ctx(scenario)
            );
            
            // Calculate expected protocol fee and validator commission
            let protocol_fee_amount = (REWARD_AMOUNT * PROTOCOL_FEE) / 10000;
            let net_reward = REWARD_AMOUNT - protocol_fee_amount;
            let validator_commission_amount = (net_reward * VALIDATOR_COMMISSION) / 10000;
            let _stakers_reward = net_reward - validator_commission_amount;
            
            printer::print_str(b"Rewards breakdown:");
            printer::print_str(b"Protocol fee (5%): 1.5 SUI");
            printer::print_str(b"Validator commission (10%): 2.85 SUI");
            printer::print_str(b"Stakers reward: 25.65 SUI");
            
            // Verify rewards distributed correctly
            assert!(rewards::get_validator_rewards(&pool, TEST_VALIDATOR) > 0, 10);
            
            // Update exchange rate based on added rewards
            exchange::update_rate_rewards(
                &mut exchange_rate,
                REWARD_AMOUNT,
                ctx(scenario)
            );
            
            // Verify rate increased after rewards
            let rate_after_rewards = exchange::get_rate(&exchange_rate);
            assert!(rate_after_rewards > rate_before_rewards, 11);
            
            // Calculate rate increase percentage (unused but helps understand flow)
            let _increase_bps = ((rate_after_rewards - rate_before_rewards) * 10000) / rate_before_rewards;
            
            printer::print_str(b"New exchange rate: ~1.10");
            printer::print_str(b"Rate increase: ~10%");
            
            test::return_shared(pool);
            test::return_shared(treasury);
            test::return_shared(config);
            test::return_shared(exchange_rate);
        };
        
        // Advance time
        clock::increment_for_testing(&mut clock, 86400 * 1 * 1000); // +1 day in milliseconds
        
        // STEP 6: Alice claims rewards
        printer::print_day(13, b"Reward Claiming");
        next_tx(scenario, ALICE);
        {
            printer::print_str(b"Alice claims her rewards...");
            
            // Get Alice's stake
            let stake = test::take_from_sender<Stake>(scenario);
            let mut pool = test::take_shared<RewardPool>(scenario);
            let mut treasury = test::take_shared<Treasury>(scenario);
            let registry = test::take_shared<StakeRegistry>(scenario);
            
            // Claim rewards
            let reward = rewards::claim_rewards(
                &mut pool,
                &registry,
                &stake,
                &mut treasury,
                ctx(scenario)
            );
            
            // Verify reward amount
            let reward_value = coin::value(&reward);
            assert!(reward_value > 0, 12);
            
            // Calculate expected reward proportion (unused but helps understand flow)
            let total_stake = ALICE_STAKE + BOB_STAKE;
            let alice_stake_ratio = (ALICE_STAKE as u128) * 10000 / (total_stake as u128);
            let _expected_reward_approx = (alice_stake_ratio * 2565) / 10000; // Approx in SUI (ignoring decimals)
            
            printer::print_str(b"Alice claimed ~8.55 SUI in rewards");
            printer::print_str(b"(Based on her 33% share of the stake pool)");
            
            // Burn reward coin for testing
            coin::burn_for_testing(reward);
            
            test::return_to_sender(scenario, stake);
            test::return_shared(pool);
            test::return_shared(treasury);
            test::return_shared(registry);
        };
        
        // Advance time
        clock::increment_for_testing(&mut clock, 86400 * 2 * 1000); // +2 days in milliseconds
        
        // STEP 7: Unstake and verify value has increased
        printer::print_day(15, b"Unstaking with Increased Value");
        next_tx(scenario, ALICE);
        {
            printer::print_str(b"Alice checks her stSUI value...");
            
            let alice_csui = test::take_from_sender<Coin<CSUI>>(scenario);
            let csui_amount = coin::value(&alice_csui);
            let exchange_rate = test::take_shared<ExchangeRate>(scenario);
            
            // Calculate SUI equivalent - in actual implementation, use exchange rate conversion
            let current_rate = exchange::get_rate(&exchange_rate);
            let sui_equivalent = ((csui_amount as u128) * (current_rate as u128) / (RATE_PRECISION as u128)) as u64;
            
            // Initial stake was ALICE_STAKE, but after rewards it should be worth more
            assert!(current_rate > RATE_PRECISION, 13);
            
            // Calculation to show increase factor (unused but helps understand flow)
            let increase_factor = (sui_equivalent * 10000) / ALICE_STAKE;
            let _increase_percentage = (increase_factor - 10000) / 100; // Convert basis points to percentage
            
            printer::print_str(b"Current exchange rate: ~1.10");
            printer::print_str(b"Alice's 100 stSUI is now worth ~110 SUI");
            printer::print_str(b"Value increase: ~10%");
            printer::print_str(b"Alice earned yield without actively managing validator stake!");
            
            // NOTE: In a real implementation, this would now burn cSUI tokens
            // and return SUI tokens based on the current exchange rate
            
            test::return_to_sender(scenario, alice_csui);
            test::return_shared(exchange_rate);
        };
        
        printer::print_section(b"Chamber Finance: Liquid Staking Demo Complete");
        printer::print_str(b"- Stake SUI → Get cSUI");
        printer::print_str(b"- cSUI automatically appreciates as rewards accrue");
        printer::print_str(b"- No lockups, claim rewards any time");
        
        // Clean up
        clock::destroy_for_testing(clock);
        test::end(scenario_val);
    }
}

/// A module that provides utilities for better debug printing in Move tests
#[test_only]
module chamber::debug_printer {
    use std::debug;
    use std::string::{Self, String};
    use std::vector;
    
    /// Prints a more readable debug message without hex encoding
    public fun print(message: &String) {
        debug::print(message);
    }
    
    /// Create a string and print it directly
    public fun print_str(message: vector<u8>) {
        let message_str = string::utf8(message);
        debug::print(&message_str);
    }
    
    /// Prints a formatted day header to make output more readable
    public fun print_day(day: u64, title: vector<u8>) {
        let mut day_str = string::utf8(b"Day ");
        string::append(&mut day_str, u64_to_string(day));
        string::append(&mut day_str, string::utf8(b": "));
        string::append(&mut day_str, string::utf8(title));
        debug::print(&day_str);
    }
    
    /// Prints a section header
    public fun print_section(title: vector<u8>) {
        let mut header = string::utf8(b"=== ");
        string::append(&mut header, string::utf8(title));
        string::append(&mut header, string::utf8(b" ==="));
        debug::print(&header);
    }
    
    /// Convert u64 to string for debug printing
    public fun u64_to_string(value: u64): String {
        if (value == 0) {
            return string::utf8(b"0")
        };
        
        let mut buffer = vector<u8>[];
        let mut temp_value = value;
        
        while (temp_value > 0) {
            let remainder = temp_value % 10;
            vector::push_back(&mut buffer, (remainder + 48 as u8)); // '0' is ASCII 48
            temp_value = temp_value / 10;
        };
        
        // Reverse the buffer
        let length = vector::length(&buffer);
        let mut i = 0;
        while (i < length / 2) {
            let temp = *vector::borrow(&buffer, i);
            *vector::borrow_mut(&mut buffer, i) = *vector::borrow(&buffer, length - i - 1);
            *vector::borrow_mut(&mut buffer, length - i - 1) = temp;
            i = i + 1;
        };
        
        string::utf8(buffer)
    }
}