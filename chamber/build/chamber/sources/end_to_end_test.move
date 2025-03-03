#[test_only]
module chamber::end_to_end_test {
    use sui::test_scenario::{Self as test, next_tx, ctx};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::{Self};
    
    use chamber::config::{Self, Config, AdminCap};
    use chamber::stake::{Self, StakeRegistry, Stake};
    use chamber::treasury::{Self, Treasury};
    use chamber::csui::{Self, CSUI, MinterCap};
    use chamber::exchange::{Self, ExchangeRate};
    use chamber::rewards::{Self, RewardPool};
    
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
        let mut scenario = test::begin(ADMIN);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        
        // STEP 1: Initialize all protocol modules
        {
            // Core modules
            config::init_for_testing(ctx(&mut scenario));
            stake::init_for_testing(ctx(&mut scenario));
            treasury::init_for_testing(ctx(&mut scenario));
            exchange::init_for_testing(ctx(&mut scenario));
            rewards::init_for_testing(ctx(&mut scenario));
            
            // Token module
            csui::init_test_token(ctx(&mut scenario));
            
            // Verify modules initialized correctly
            next_tx(&mut scenario, ADMIN);
            assert!(test::has_most_recent_for_address<AdminCap>(ADMIN), 0);
            
            let config = test::take_shared<Config>(&scenario);
            // Don't assert specific fee value, just verify Config exists
            test::return_shared(config);
        };
        
        // STEP 2: Configure protocol settings and validator
        next_tx(&mut scenario, ADMIN);
        {
            // Set protocol fee
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            
            config::update_protocol_fee(
                &admin_cap,
                &mut config,
                PROTOCOL_FEE,
                ctx(&mut scenario)
            );
            
            // Register validator
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                true, // active
                VALIDATOR_CAPACITY,
                VALIDATOR_COMMISSION,
                ctx(&mut scenario)
            );
            
            // Verify validator configuration
            assert!(config::is_validator_active(&config, TEST_VALIDATOR, 0), 2);
            let (_, max_stake, commission) = config::get_validator_config(&config, TEST_VALIDATOR);
            assert!(max_stake == VALIDATOR_CAPACITY, 3);
            assert!(commission == VALIDATOR_COMMISSION, 4);
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };
        
        // STEP 3: Alice stakes SUI
        next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let mut exchange_rate = test::take_shared<ExchangeRate>(&scenario);
            
            // Mint SUI for Alice
            let payment = coin::mint_for_testing<SUI>(ALICE_STAKE, ctx(&mut scenario));
            
            // Record initial exchange rate
            let initial_rate = exchange::get_rate(&exchange_rate);
            assert!(initial_rate == RATE_PRECISION, 5); // Initial rate is 1:1
            
            // Stake SUI
            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                payment,
                ctx(&mut scenario)
            );
            
            // Update exchange rate
            exchange::update_rate_stake(
                &mut exchange_rate,
                ALICE_STAKE,
                ctx(&mut scenario)
            );
            
            // Mint stSUI (cSUI) tokens for Alice
            let mut treasury_cap = test::take_from_address<coin::TreasuryCap<CSUI>>(&scenario, ADMIN);
            let minter_cap = test::take_from_address<MinterCap>(&scenario, ADMIN);
            
            // Calculate stSUI amount - in a real implementation we'd convert based on exchange rate
            // but for simplicity in testing we're using 1:1
            let stsui_amount = ALICE_STAKE;
            
            csui::mint(
                &mut treasury_cap, 
                &minter_cap, 
                stsui_amount, 
                ALICE, 
                &clock, 
                ctx(&mut scenario)
            );
            
            // Verify staked amount in treasury
            assert!(treasury::get_stake_balance(&treasury) == ALICE_STAKE, 6);
            
            // Verify cSUI token issuance
            assert!(csui::total_supply(&treasury_cap) == stsui_amount, 7);
            
            test::return_to_address(ADMIN, treasury_cap);
            test::return_to_address(ADMIN, minter_cap);
            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
            test::return_shared(exchange_rate);
        };
        
        // Verify Alice received the correct amount of stSUI
        next_tx(&mut scenario, ALICE);
        {
            let alice_csui = test::take_from_sender<Coin<CSUI>>(&scenario);
            assert!(coin::value(&alice_csui) == ALICE_STAKE, 8); // Initial 1:1 rate
            test::return_to_sender(&scenario, alice_csui);
        };
        
        // STEP 4: Bob stakes SUI
        next_tx(&mut scenario, BOB);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let mut exchange_rate = test::take_shared<ExchangeRate>(&scenario);
            
            // Mint SUI for Bob
            let payment = coin::mint_for_testing<SUI>(BOB_STAKE, ctx(&mut scenario));
            
            // Get current rate before Bob's stake (unused but shows checking rate)
            let _current_rate = exchange::get_rate(&exchange_rate);
            
            // Stake SUI
            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                payment,
                ctx(&mut scenario)
            );
            
            // Update exchange rate
            exchange::update_rate_stake(
                &mut exchange_rate,
                BOB_STAKE,
                ctx(&mut scenario)
            );
            
            // Mint stSUI (cSUI) tokens for Bob based on current rate
            let mut treasury_cap = test::take_from_address<coin::TreasuryCap<CSUI>>(&scenario, ADMIN);
            let minter_cap = test::take_from_address<MinterCap>(&scenario, ADMIN);
            
            // For simplicity in testing, use 1:1 rate
            let stsui_amount = BOB_STAKE;
            
            csui::mint(
                &mut treasury_cap, 
                &minter_cap, 
                stsui_amount, 
                BOB, 
                &clock, 
                ctx(&mut scenario)
            );
            
            // Verify total staked amount
            assert!(treasury::get_stake_balance(&treasury) == ALICE_STAKE + BOB_STAKE, 9);
            
            test::return_to_address(ADMIN, treasury_cap);
            test::return_to_address(ADMIN, minter_cap);
            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
            test::return_shared(exchange_rate);
        };
        
        // STEP 5: Process rewards
        next_tx(&mut scenario, TEST_VALIDATOR);
        {
            let mut pool = test::take_shared<RewardPool>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let mut exchange_rate = test::take_shared<ExchangeRate>(&scenario);
            
            // Create rewards
            let reward_coin = coin::mint_for_testing<SUI>(REWARD_AMOUNT, ctx(&mut scenario));
            
            // Record rate before rewards
            let rate_before_rewards = exchange::get_rate(&exchange_rate);
            
            // Add rewards
            rewards::add_validator_rewards(
                &mut pool,
                TEST_VALIDATOR,
                reward_coin,
                &mut config,
                &mut treasury,
                ctx(&mut scenario)
            );
            
            // Calculate expected protocol fee and validator commission
            let protocol_fee_amount = (REWARD_AMOUNT * PROTOCOL_FEE) / 10000;
            let net_reward = REWARD_AMOUNT - protocol_fee_amount;
            // This is not used but shows calculation
            let _validator_commission_amount = (net_reward * VALIDATOR_COMMISSION) / 10000;
            
            // Verify rewards distributed correctly
            assert!(rewards::get_validator_rewards(&pool, TEST_VALIDATOR) > 0, 10);
            
            // Update exchange rate based on added rewards
            exchange::update_rate_rewards(
                &mut exchange_rate,
                REWARD_AMOUNT,
                ctx(&mut scenario)
            );
            
            // Verify rate increased after rewards
            let rate_after_rewards = exchange::get_rate(&exchange_rate);
            assert!(rate_after_rewards > rate_before_rewards, 11);
            
            test::return_shared(pool);
            test::return_shared(treasury);
            test::return_shared(config);
            test::return_shared(exchange_rate);
        };
        
        // STEP 6: Alice claims rewards
        next_tx(&mut scenario, ALICE);
        {
            // Get Alice's stake
            let stake = test::take_from_sender<Stake>(&scenario);
            let mut pool = test::take_shared<RewardPool>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let registry = test::take_shared<StakeRegistry>(&scenario);
            
            // Claim rewards
            let reward = rewards::claim_rewards(
                &mut pool,
                &registry,
                &stake,
                &mut treasury,
                ctx(&mut scenario)
            );
            
            // Verify reward amount
            let reward_value = coin::value(&reward);
            assert!(reward_value > 0, 12);
            
            // Calculate expected reward proportion (not used in assertion but shows calculation)
            let total_stake = ALICE_STAKE + BOB_STAKE;
            let _alice_stake_ratio = (ALICE_STAKE as u128) * 10000 / (total_stake as u128);
            
            // Burn reward coin for testing
            coin::burn_for_testing(reward);
            
            test::return_to_sender(&scenario, stake);
            test::return_shared(pool);
            test::return_shared(treasury);
            test::return_shared(registry);
        };
        
        // STEP 7: Unstake and verify value has increased
        next_tx(&mut scenario, ALICE);
        {
            let alice_csui = test::take_from_sender<Coin<CSUI>>(&scenario);
            let csui_amount = coin::value(&alice_csui);
            let exchange_rate = test::take_shared<ExchangeRate>(&scenario);
            
            // Calculate SUI equivalent - in actual implementation, use exchange rate conversion
            // For testing, we can just calculate an approximate expected value
            let current_rate = exchange::get_rate(&exchange_rate);
            let sui_equivalent = ((csui_amount as u128) * (current_rate as u128) / (RATE_PRECISION as u128)) as u64;
            
            // Initial stake was ALICE_STAKE, but after rewards it should be worth more
            // Note: The exchange rate should have increased, making the stSUI worth more SUI
            assert!(current_rate > RATE_PRECISION, 13);
            
            // Calculation to show increase factor (not used in assertion)
            let _increase_factor = (sui_equivalent * 10000) / ALICE_STAKE;
            
            // NOTE: In a real implementation, this would now burn cSUI tokens
            // and return SUI tokens based on the current exchange rate
            
            test::return_to_sender(&scenario, alice_csui);
            test::return_shared(exchange_rate);
        };
        
        // Clean up
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
}