module chamber::protocol_admin_tests {
    use sui::test_scenario::{Self as test};
    use sui::coin::{Self};
    use sui::sui::SUI;
    
    use chamber::config::{Self, Config, AdminCap};
    use chamber::stake::{Self, StakeRegistry};
    use chamber::treasury::{Self, Treasury};
    use chamber::math;

    // Test constants
    const TEST_ADMIN: address = @0xAD;
    const ALICE: address = @0x42;
    const INITIAL_FEE_RATE: u64 = 1000; // 10%
    const NEW_FEE_RATE: u64 = 500;      // 5%
    const VALID_STAKE: u64 = 5_000_000_000;
    const TEST_VALIDATOR: address = @0x1001;

    fun setup_test(scenario: &mut test::Scenario) {
        test::next_tx(scenario, TEST_ADMIN);
        {
            config::init_for_testing(test::ctx(scenario));
            stake::init_for_testing(test::ctx(scenario));
            treasury::init_for_testing(test::ctx(scenario));
        };
    }

    #[test]
    fun test_protocol_fee_update() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        // Set initial protocol fee rate
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            // Set initial fee rate
            config::update_protocol_fee(
                &admin_cap,
                &mut config,
                INITIAL_FEE_RATE,
                test::ctx(&mut scenario)
            );

            // Verify initial fee rate
            assert!(config::get_protocol_fee(&config) == INITIAL_FEE_RATE, 1);

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        // Update protocol fee rate
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            // Update to new fee rate
            config::update_protocol_fee(
                &admin_cap,
                &mut config,
                NEW_FEE_RATE,
                test::ctx(&mut scenario)
            );

            // Verify fee rate was updated
            assert!(config::get_protocol_fee(&config) == NEW_FEE_RATE, 2);

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        // Create stake to verify new fee is applied
        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let payment = coin::mint_for_testing<SUI>(VALID_STAKE, test::ctx(&mut scenario));

            // Get admin cap from TEST_ADMIN to add validator
            test::next_tx(&mut scenario, TEST_ADMIN);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            
            // Add validator and stake
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                true,
                VALID_STAKE * 2, // max stake
                1000,
                test::ctx(&mut scenario)
            );

            test::return_to_sender(&scenario, admin_cap);
            test::next_tx(&mut scenario, ALICE);

            // Stake with new fee rate
            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                payment,
                test::ctx(&mut scenario)
            );

            // Verify total stakes increased
            assert!(config::get_total_staked(&config) > 0, 3);

            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = config::E_INVALID_PARAMETER)]
    fun test_protocol_fee_exceeds_maximum() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            // Try to set fee rate above maximum (10000 basis points = 100%)
            config::update_protocol_fee(
                &admin_cap,
                &mut config,
                10001,
                test::ctx(&mut scenario)
            );

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = config::E_NOT_AUTHORIZED)]
    fun test_unauthorized_fee_update() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        // Try to update fee rate from non-admin account
        test::next_tx(&mut scenario, ALICE);
        {
            let mut config = test::take_shared<Config>(&scenario);
            // Create test admin cap which will have nonce = 0
            let fake_admin_cap = config::create_admin_cap_for_testing(test::ctx(&mut scenario));

            // This should fail with E_NOT_AUTHORIZED since this admin cap has wrong nonce
            config::update_protocol_fee(
                &fake_admin_cap,
                &mut config,
                NEW_FEE_RATE,
                test::ctx(&mut scenario)
            );

            test::return_shared(config);
            transfer::public_transfer(fake_admin_cap, ALICE);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = config::E_INVALID_PARAMETER)]
    fun test_min_stake_exceeds_current_max() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            let current_max = config::get_max_stake(&config);
            
            // Try to set min stake higher than current max stake
            config::update_min_stake(
                &admin_cap,
                &mut config,
                current_max + 1
            );

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = config::E_INVALID_PARAMETER)]
    fun test_max_stake_below_current_min() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            let current_min = config::get_min_stake(&config);
            config::update_max_stake(
                &admin_cap,
                &mut config,
                current_min - 1,
                test::ctx(&mut scenario)
            );

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = config::E_RATE_LIMITED)]
    fun test_fee_update_rate_limit() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        // First update
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            
            // Set initial timestamp
            test::next_epoch(&mut scenario, TEST_ADMIN);
            
            config::update_protocol_fee(
                &admin_cap, 
                &mut config, 
                1000,
                test::ctx(&mut scenario)
            );
            
            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        // Try immediate second update - should fail due to rate limit
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            
            // Advance by another epoch which should be less than MIN_UPDATE_DELAY
            test::next_epoch(&mut scenario, TEST_ADMIN);
            
            // This should fail because MIN_UPDATE_DELAY hasn't passed
            config::update_protocol_fee(
                &admin_cap, 
                &mut config, 
                2000,
                test::ctx(&mut scenario)
            );
            
            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = config::E_CHANGE_TOO_LARGE)]
    fun test_max_stake_change_limit() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            
            let current_max = config::get_max_stake(&config);
            // Try to increase max stake by more than MAX_STAKE_CHANGE_PERCENTAGE
            let new_max = current_max + ((current_max * 6000) / 10000); // 60% increase
            
            config::update_max_stake(
                &admin_cap,
                &mut config,
                new_max,
                test::ctx(&mut scenario)
            );
            
            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        test::end(scenario);
    }

    #[test]
    fun test_max_stake_valid_change() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            
            let current_max = config::get_max_stake(&config);
            // Try to increase max stake by less than MAX_STAKE_CHANGE_PERCENTAGE
            let new_max = current_max + ((current_max * 4000) / 10000); // 40% increase
            
            config::update_max_stake(
                &admin_cap,
                &mut config,
                new_max,
                test::ctx(&mut scenario)
            );
            assert!(config::get_max_stake(&config) == new_max, 1);
            
            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        test::end(scenario);
    }

    #[test]
    fun test_zero_fee_update() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            
            // Reset the last update time to bypass rate limiting
            config::reset_last_fee_update_for_testing(&mut config);
            
            // Setting fee to zero should be valid
            config::update_protocol_fee(
                &admin_cap,
                &mut config,
                0,
                test::ctx(&mut scenario)
            );
            
            assert!(config::get_protocol_fee(&config) == 0, 1);

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };
        test::end(scenario);
    }

    #[test]
    fun test_consecutive_valid_stake_updates() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            
            // First update - increase by 40%
            let current_max = config::get_max_stake(&config);
            let new_max = current_max + ((current_max * 4000) / 10000);
            
            config::reset_last_stake_update_for_testing(&mut config, test::ctx(&mut scenario));
            config::update_max_stake(
                &admin_cap,
                &mut config,
                new_max,
                test::ctx(&mut scenario)
            );
            
            // Second update after delay
            test::next_epoch(&mut scenario, TEST_ADMIN);
            
            let final_max = new_max + ((new_max * 4000) / 10000);
            config::reset_last_stake_update_for_testing(&mut config, test::ctx(&mut scenario));
            config::update_max_stake(
                &admin_cap,
                &mut config,
                final_max,
                test::ctx(&mut scenario)
            );
            
            assert!(config::get_max_stake(&config) == final_max, 1);

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };
        test::end(scenario);
    }

    #[test]
    fun test_max_protocol_fee() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);
        
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            
            config::reset_last_fee_update_for_testing(&mut config);
            
            // Update fee in smaller increments
            let target_fee = 10000;
            let increment = 1000; // Conservative increment size that should be below MAX_FEE_CHANGE
            let mut current_fee = config::get_protocol_fee(&config);
            
            while (current_fee < target_fee) {
                let next_fee = math::min(current_fee + increment, target_fee);
                config::update_protocol_fee(
                    &admin_cap,
                    &mut config,
                    next_fee,
                    test::ctx(&mut scenario)
                );
                current_fee = next_fee;
                
                // Reset rate limiting if needed
                config::reset_last_fee_update_for_testing(&mut config);
            };
            
            assert!(config::get_protocol_fee(&config) == 10000, 1);
            
            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };
        test::end(scenario);
    }

    #[test]
    fun test_emergency_withdrawal_enable() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            
            // Initially emergency mode should be disabled
            assert!(!config::is_emergency_mode(&config), 0);
            
            // Enable emergency mode
            config::set_emergency_mode(&admin_cap, &mut config, true);
            assert!(config::is_emergency_mode(&config), 1);
            
            // Disable emergency mode
            config::set_emergency_mode(&admin_cap, &mut config, false);
            assert!(!config::is_emergency_mode(&config), 2);

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };
        test::end(scenario);
    }
    
    #[test]
    fun test_emergency_withdrawal_processing() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        // First transaction: Set up a stake as ALICE
        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let payment = coin::mint_for_testing<SUI>(VALID_STAKE, test::ctx(&mut scenario));

            // Nested admin transaction to set up validator
            test::next_tx(&mut scenario, TEST_ADMIN);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                true,  // active
                VALID_STAKE * 2,  // max stake
                1000,
                test::ctx(&mut scenario)
            );
            test::return_to_sender(&scenario, admin_cap);

            // Back to ALICE's transaction to create stake
            test::next_tx(&mut scenario, ALICE);
            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                payment,
                test::ctx(&mut scenario)
            );

            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };

        // Second transaction: Admin enables emergency mode and processes withdrawal
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            // Enable emergency mode
            config::set_emergency_mode(&admin_cap, &mut config, true);
            
            // Process emergency withdrawal
            stake::emergency_withdraw(
                &mut registry,
                &mut treasury,
                &mut config,
                test::ctx(&mut scenario)
            );

            // Verify all stake has been withdrawn
            assert!(config::get_total_staked(&config) == 0, 1);
            
            test::return_shared(config);
            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_to_sender(&scenario, admin_cap);
        };
        test::end(scenario);
    }
}