#[test_only]
module chamber::error_case_tests {
    use sui::test_scenario::{Self as test, Scenario};
    use sui::coin::{Self};
    use sui::sui::SUI;
    use chamber::config::{Self, Config, AdminCap};
    use chamber::stake::{Self, StakeRegistry, Stake};
    use chamber::treasury::{Self, Treasury};
    use chamber::validation;

    // Test addresses
    const TEST_ADMIN: address = @0x1234;
    const TEST_VALIDATOR: address = @0x5678;
    const ALICE: address = @0x1111;

    // Test amounts
    const BELOW_MIN_STAKE: u64 = 500_000;
    const VALID_STAKE: u64 = 1000 * 1_000_000_000; // 1000 SUI
    const SYSTEM_CAPACITY: u64 = 100_000_000_000_000;
    const MAX_VALIDATOR_STAKE: u64 = 10000 * 1_000_000_000; // 10000 SUI

    // Error codes from config module
    const E_VALIDATOR_NOT_FOUND: u64 = 2;

    // Error codes from stake module
    const E_STAKE_NOT_FOUND: u64 = 1;
    const E_STAKE_EXCEEDS_CAPACITY: u64 = 3;

    // Error codes from validation module
    const E_BELOW_MINIMUM: u64 = 1;
    const E_SYSTEM_CAPACITY_EXCEEDED: u64 = 8;

    // Error codes from treasury module
    const E_INSUFFICIENT_BALANCE: u64 = 0;

    #[test]
    #[expected_failure(abort_code = E_BELOW_MINIMUM, location = chamber::validation)]
    fun test_stake_below_minimum() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_protocol(&mut scenario);

        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);

            let payment = coin::mint_for_testing<SUI>(BELOW_MIN_STAKE, test::ctx(&mut scenario));
            
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
    #[expected_failure(abort_code = E_VALIDATOR_NOT_FOUND, location = chamber::config)]
    fun test_stake_invalid_validator() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_protocol(&mut scenario);

        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);

            let payment = coin::mint_for_testing<SUI>(VALID_STAKE, test::ctx(&mut scenario));
            
            let invalid_validator = @0xDEAD;
            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                invalid_validator,
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
    #[expected_failure(abort_code = E_SYSTEM_CAPACITY_EXCEEDED, location = chamber::validation)]
    fun test_system_capacity_exceeded() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_protocol(&mut scenario);

        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            
            // Stake amount slightly over system capacity
            let stake_amount = SYSTEM_CAPACITY + validation::get_min_stake();
            let payment = coin::mint_for_testing<SUI>(stake_amount, test::ctx(&mut scenario));
            
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
    #[expected_failure(abort_code = E_STAKE_EXCEEDS_CAPACITY, location = chamber::stake)]
    fun test_stake_exceeds_validator_capacity() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_protocol(&mut scenario);

        // First stake up to validator capacity
        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);

            let payment = coin::mint_for_testing<SUI>(MAX_VALIDATOR_STAKE, test::ctx(&mut scenario));
            
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

        // Try to stake more, should fail
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
    #[expected_failure(abort_code = E_STAKE_NOT_FOUND, location = chamber::stake)]
    fun test_stake_not_found() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_protocol(&mut scenario);

        // First stake a valid amount
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

        // Try to withdraw with a non-existent stake
        test::next_tx(&mut scenario, TEST_VALIDATOR); // Different address than staker
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let config = test::take_shared<Config>(&scenario);

            let fake_stake = stake::create_stake_for_testing(
                TEST_VALIDATOR,
                VALID_STAKE,
                0,
                test::ctx(&mut scenario)
            );
            
            stake::withdraw(
                &mut registry,
                fake_stake,
                &mut treasury,
                &config,
                test::ctx(&mut scenario)
            );

            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = E_INSUFFICIENT_BALANCE, location = chamber::treasury)]
    fun test_reward_distribution_insufficient_balance() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_protocol(&mut scenario);

        // Setup initial stake
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

        // Try to distribute rewards with insufficient balance
        test::next_tx(&mut scenario, TEST_ADMIN);  // Changed from TEST_VALIDATOR to TEST_ADMIN
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let config = test::take_shared<Config>(&scenario);

            // Try to distribute more rewards than available in treasury
            let (reward_coin, fee_coin) = treasury::distribute_rewards(
                &admin_cap,
                &mut treasury,
                &config,
                TEST_VALIDATOR,
                VALID_STAKE * 2, // Try to distribute more than what's available
                test::ctx(&mut scenario)
            );

            // Transfer the coins
            transfer::public_transfer(reward_coin, TEST_VALIDATOR);
            transfer::public_transfer(fee_coin, TEST_ADMIN);

            test::return_to_sender(&scenario,  admin_cap);
            test::return_shared(treasury);
            test::return_shared(config);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = stake::E_STAKE_NOT_FOUND)]
    fun test_concurrent_withdrawals() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_protocol(&mut scenario);

        // First stake
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

        // First withdrawal - this should succeed
        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let config = test::take_shared<Config>(&scenario);
            let stake_obj = test::take_from_sender<Stake>(&scenario);
            
            stake::withdraw(
                &mut registry,
                stake_obj,
                &mut treasury,
                &config,
                test::ctx(&mut scenario)
            );

            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };

        // Second withdrawal - this should fail as stake is already withdrawn
        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let config = test::take_shared<Config>(&scenario);
            
            // Create a fake stake object to try withdrawing again
            let fake_stake = stake::create_stake_for_testing(
                TEST_VALIDATOR,
                VALID_STAKE,
                0,
                test::ctx(&mut scenario)
            );
            
            // This should fail as the stake entry has been removed in first withdrawal
            stake::withdraw(
                &mut registry,
                fake_stake,
                &mut treasury,
                &config,
                test::ctx(&mut scenario)
            );

            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };
        test::end(scenario);
    }

    // Helper function
    fun setup_protocol(scenario: &mut Scenario) {
        test::next_tx(scenario, TEST_ADMIN);
        {
            config::init_for_testing(test::ctx(scenario));
            stake::init_for_testing(test::ctx(scenario));
            treasury::init_for_testing(test::ctx(scenario));
        };

        test::next_tx(scenario, TEST_ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(scenario);
            let mut config = test::take_shared<Config>(scenario);
            
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                true,
                MAX_VALIDATOR_STAKE,
                1000,
                test::ctx(scenario)
            );

            test::return_to_sender(scenario, admin_cap);
            test::return_shared(config);
        };
    }
}