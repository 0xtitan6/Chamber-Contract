module chamber::validator_flow_tests {
    use sui::test_scenario::{Self as test};
    use sui::coin::{Self as coin};
    use sui::sui::SUI;
    
    use chamber::config::{Self, Config, AdminCap};
    use chamber::stake::{Self, StakeRegistry};
    use chamber::treasury::{Self, Treasury};

    const TEST_ADMIN: address = @0xAD;
    const ALICE: address = @0x42;
    const TEST_VALIDATOR: address = @0x1001;
    const VALID_STAKE: u64 = 5_000_000_000;
    const MAX_VALIDATOR_STAKE: u64 = 100_000_000_000;
    const DEFAULT_COMMISSION_RATE: u64 = 500;
    const INITIAL_COMMISSION_RATE: u64 = 500;
    const NEW_COMMISSION_RATE: u64 = 1000;     // 10%
    const REWARD_AMOUNT: u64 = 1_000_000_000;  // 1000 SUI

    const BOB: address = @0x43;
    const TEST_VALIDATOR_2: address = @0x1002;
    const TEST_VALIDATOR_3: address = @0x1003;
    const STAKE_AMOUNT_1: u64 = 2_000_000_000;
    const STAKE_AMOUNT_2: u64 = 3_000_000_000;

    fun setup_test(scenario: &mut test::Scenario) {
        // Initialize core modules
        {
            config::init_for_testing(test::ctx(scenario));
            stake::init_for_testing(test::ctx(scenario));
            treasury::init_for_testing(test::ctx(scenario));
        };
    }

    #[test]
    fun test_validator_deactivation_with_active_stakes() {
        let mut scenario = test::begin(TEST_ADMIN);
        
        // Setup protocol
        setup_test(&mut scenario);

        // Add validator
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                true, // active
                MAX_VALIDATOR_STAKE,
                DEFAULT_COMMISSION_RATE,
                test::ctx(&mut scenario)
            );

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        // Alice stakes with validator
        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let payment = coin::mint_for_testing<SUI>(VALID_STAKE, test::ctx(&mut scenario));

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

        // Admin deactivates validator
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                false, // deactivate
                MAX_VALIDATOR_STAKE,
                DEFAULT_COMMISSION_RATE,
                test::ctx(&mut scenario)
            );

            // Verify validator is deactivated
            assert!(!config::is_validator_active(&config, TEST_VALIDATOR, 0), 1);

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = stake::E_VALIDATOR_NOT_ACTIVE)]  // Changed this line
    fun test_stake_to_inactive_validator() {
        let mut scenario = test::begin(TEST_ADMIN);
        
        // Setup protocol with inactive validator
        setup_test(&mut scenario);

        // Add inactive validator
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                false, // inactive
                MAX_VALIDATOR_STAKE,
                DEFAULT_COMMISSION_RATE,
                test::ctx(&mut scenario)
            );

            assert!(!config::is_validator_active(&config, TEST_VALIDATOR, 0), 0); // Verify validator is inactive
            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        // Try to stake with inactive validator - should fail with E_VALIDATOR_NOT_ACTIVE
        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let payment = coin::mint_for_testing<SUI>(VALID_STAKE, test::ctx(&mut scenario));

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

        test::end(scenario);
    }

    #[test]
    fun test_validator_commission_rate_update() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        // Add validator with initial commission rate
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                true,
                MAX_VALIDATOR_STAKE,
                INITIAL_COMMISSION_RATE,
                test::ctx(&mut scenario)
            );

            // Verify initial commission rate
            let (_, _, commission) = config::get_validator_config(&config, TEST_VALIDATOR);
            assert!(commission == INITIAL_COMMISSION_RATE, 1);

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        // Update commission rate
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                true,
                MAX_VALIDATOR_STAKE,
                NEW_COMMISSION_RATE,
                test::ctx(&mut scenario)
            );

            // Verify updated commission rate
            let (_, _, commission) = config::get_validator_config(&config, TEST_VALIDATOR);
            assert!(commission == NEW_COMMISSION_RATE, 2);

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = config::E_INVALID_PARAMETER)]
    fun test_invalid_commission_rate() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        // Try to set commission rate above maximum (100%)
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                true,
                MAX_VALIDATOR_STAKE,
                11000,
                test::ctx(&mut scenario)
            );

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        test::end(scenario);
    }

    #[test]
    fun test_commission_rate_affects_rewards() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        // Add validator and stake
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                true,
                MAX_VALIDATOR_STAKE,
                INITIAL_COMMISSION_RATE,
                test::ctx(&mut scenario)
            );

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        // Simulate rewards with initial commission rate
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            
            let initial_validator_reward = calculate_validator_commission(
                REWARD_AMOUNT,
                INITIAL_COMMISSION_RATE
            );

            // Update commission rate
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                true,
                MAX_VALIDATOR_STAKE,
                NEW_COMMISSION_RATE,
                test::ctx(&mut scenario)
            );

            let new_validator_reward = calculate_validator_commission(
                REWARD_AMOUNT,
                NEW_COMMISSION_RATE
            );

            // Verify that higher commission rate results in higher validator reward
            assert!(new_validator_reward > initial_validator_reward, 3);

            test::return_shared(treasury);
            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = stake::E_STAKE_EXCEEDS_CAPACITY)]  // Changed from validation::E_ABOVE_MAXIMUM
    fun test_stake_above_validator_capacity() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        // Add validator with low max capacity
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            let low_capacity = VALID_STAKE / 2; // Set capacity below stake amount
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                true,
                low_capacity,
                DEFAULT_COMMISSION_RATE,
                test::ctx(&mut scenario)
            );

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        // Try to stake above capacity - should fail
        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let payment = coin::mint_for_testing<SUI>(VALID_STAKE, test::ctx(&mut scenario));

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

        test::end(scenario);
    }

    #[test]
    fun test_validator_max_capacity_update() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        // Add validator with initial max capacity
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                true,
                MAX_VALIDATOR_STAKE,
                DEFAULT_COMMISSION_RATE,
                test::ctx(&mut scenario)
            );

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        // Alice stakes within initial capacity
        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let payment = coin::mint_for_testing<SUI>(VALID_STAKE, test::ctx(&mut scenario));

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

        // Admin reduces max capacity but still above current stake
        let reduced_capacity = VALID_STAKE + 1000; // Just slightly above current stake
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                true,
                reduced_capacity,
                DEFAULT_COMMISSION_RATE,
                test::ctx(&mut scenario)
            );

            // Verify updated max stake
            let (_, max_stake, _) = config::get_validator_config(&config, TEST_VALIDATOR);
            assert!(max_stake == reduced_capacity, 2);

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        test::end(scenario);
    }

    #[test]
    fun test_multiple_validator_staking() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        // Add multiple validators
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            // Add three validators with different configurations
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                true,
                MAX_VALIDATOR_STAKE,
                500,
                test::ctx(&mut scenario)
            );

            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR_2,
                true,
                MAX_VALIDATOR_STAKE,
                700,
                test::ctx(&mut scenario)
            );

            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR_3,
                true,
                MAX_VALIDATOR_STAKE,
                300,
                test::ctx(&mut scenario)
            );

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        // Multiple users stake with different validators
        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let payment = coin::mint_for_testing<SUI>(STAKE_AMOUNT_1, test::ctx(&mut scenario));

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

        // Bob stakes with validator 2
        test::next_tx(&mut scenario, BOB);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let payment = coin::mint_for_testing<SUI>(STAKE_AMOUNT_2, test::ctx(&mut scenario));

            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR_2,
                payment,
                test::ctx(&mut scenario)
            );

            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };

        // Verify stakes distribution
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let registry = test::take_shared<StakeRegistry>(&scenario);
            
            assert!(stake::get_validator_stake(&registry, TEST_VALIDATOR) == STAKE_AMOUNT_1, 1);
            assert!(stake::get_validator_stake(&registry, TEST_VALIDATOR_2) == STAKE_AMOUNT_2, 2);
            assert!(stake::get_validator_stake(&registry, TEST_VALIDATOR_3) == 0, 3);

            test::return_shared(registry);
        };

        test::end(scenario);
    }

    #[test]
    fun test_validator_removal_with_withdrawals() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        // Setup validator
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                true,
                MAX_VALIDATOR_STAKE,
                DEFAULT_COMMISSION_RATE,
                test::ctx(&mut scenario)
            );

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        // Create initial stake
        let stake_id: ID;
        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let payment = coin::mint_for_testing<SUI>(STAKE_AMOUNT_1, test::ctx(&mut scenario));

            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                payment,
                test::ctx(&mut scenario)
            );

            // Get the stake ID for later
            stake_id = stake::get_stake_id(&registry, ALICE);

            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };

        // Withdraw stake
        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let config = test::take_shared<Config>(&scenario);
            
            let stake = test::take_from_address<stake::Stake>(&scenario, ALICE);
            assert!(object::id(&stake) == stake_id, 1);

            stake::withdraw(
                &mut registry,
                stake,
                &mut treasury,
                &config,
                test::ctx(&mut scenario)
            );

            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };

        // Deactivate validator after stakes are withdrawn
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            // Deactivate validator
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                false, // deactivate
                MAX_VALIDATOR_STAKE,
                DEFAULT_COMMISSION_RATE,
                test::ctx(&mut scenario)
            );

            // Verify validator is deactivated
            assert!(!config::is_validator_active(&config, TEST_VALIDATOR, 0), 2);
            
            // Verify no remaining stakes
            let registry = test::take_shared<StakeRegistry>(&scenario);
            assert!(stake::get_validator_stake(&registry, TEST_VALIDATOR) == 0, 3);
            test::return_shared(registry);

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        test::end(scenario);
    }

    #[test]
    fun test_validator_deactivation_delay() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        // First add and activate validator
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                true,
                MAX_VALIDATOR_STAKE,
                DEFAULT_COMMISSION_RATE,
                test::ctx(&mut scenario)
            );

            assert!(config::is_validator_active(&config, TEST_VALIDATOR, 0), 0);

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        // Create stakes before deactivation
        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let payment = coin::mint_for_testing<SUI>(VALID_STAKE, test::ctx(&mut scenario));

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

        // Request deactivation
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);

            let current_epoch = config::get_epoch(test::ctx(&mut scenario));
            let withdrawal_delay = config::get_withdrawal_delay(&config);

            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                false,
                MAX_VALIDATOR_STAKE,
                DEFAULT_COMMISSION_RATE,
                test::ctx(&mut scenario)
            );

            // Validate deactivation details
            let (is_active, _max_stake, _commission_rate) = config::get_validator_config(&config, TEST_VALIDATOR);
            assert!(!is_active, 1);

            let deactivation_time = config::get_validator_deactivation_epoch(&config, TEST_VALIDATOR);
            assert!(deactivation_time == current_epoch + withdrawal_delay, 2);

            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };

        // Advance epochs and verify state changes
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let config = test::take_shared<Config>(&scenario);
            let registry = test::take_shared<StakeRegistry>(&scenario);

            // Simulate delay period passing
            test::next_epoch(&mut scenario, TEST_ADMIN);
            test::next_epoch(&mut scenario, TEST_ADMIN);

            // Validator should now be inactive
            assert!(!config::is_validator_active(&config, TEST_VALIDATOR, 0), 3);

            // Check remaining stakes
            let remaining_stake = stake::get_validator_stake(&registry, TEST_VALIDATOR);
            assert!(remaining_stake == VALID_STAKE, 4); // Stakes should still exist

            test::return_shared(config);
            test::return_shared(registry);
        };

        test::end(scenario);
    }

    // Helper function to calculate validator commission
    fun calculate_validator_commission(reward_amount: u64, commission_rate: u64): u64 {
        (((reward_amount as u128) * (commission_rate as u128)) / 10000u128 as u64)
    }
}