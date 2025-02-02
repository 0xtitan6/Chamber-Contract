#[test_only]
module chamber::delegation_pool_tests {
    use sui::test_scenario::{Self as test};
    use sui::coin::mint_for_testing;
    use sui::sui::SUI;
    
    use chamber::delegation_pool::{Self, DelegationPool};
    use chamber::stake::{Self, StakeRegistry};
    use chamber::treasury::{Self, Treasury};
    use chamber::config::{Self, Config, AdminCap};

    const ADMIN: address = @0xAD;
    const USER: address = @0xCAFE;
    const VALIDATOR: address = @0xCAB;
    const MIN_STAKE: u64 = 1_000_000_000;
    const MAX_STAKE: u64 = 1000 * 1_000_000_000;

    fun setup_test(scenario: &mut test::Scenario) {
        test::next_tx(scenario, ADMIN);
        {
            delegation_pool::init_for_testing(test::ctx(scenario));
            stake::init_for_testing(test::ctx(scenario));
            treasury::init_for_testing(test::ctx(scenario));
            config::init_for_testing(test::ctx(scenario));
        };

        // Setup validator in config
        test::next_tx(scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(scenario);
            let mut config = test::take_shared<Config>(scenario);

            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                VALIDATOR,
                true, // active
                MAX_STAKE,
                1000, // 10% commission
                test::ctx(scenario)
            );

            // Return shared object first
            test::return_shared(config);
            // Now return the admin cap with a reference to scenario
            test::return_to_sender(scenario, admin_cap);
        };
    }

    #[test]
    fun test_initialization() {
        let mut scenario = test::begin(ADMIN);
        {
            delegation_pool::init_for_testing(test::ctx(&mut scenario));
        };
        test::end(scenario);
    }

    #[test]
    fun test_deposit() {
        let mut scenario = test::begin(ADMIN);
        setup_test(&mut scenario);

        test::next_tx(&mut scenario, USER);
        {
            let mut pool = test::take_shared<DelegationPool>(&scenario);
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let payment = mint_for_testing<SUI>(MIN_STAKE, test::ctx(&mut scenario));

            delegation_pool::deposit(
                &mut pool,
                &mut registry,
                &mut treasury,
                &mut config,
                VALIDATOR,
                payment,
                test::ctx(&mut scenario)
            );

            // Verify pool state
            let pool_balance = delegation_pool::get_total_sui_staked(&pool);
            assert!(pool_balance == MIN_STAKE, 0);

            // Verify registry state
            let registry_stake = stake::get_validator_stake(&registry, VALIDATOR);
            assert!(registry_stake == MIN_STAKE, 1);

            // Verify treasury state
            let treasury_balance = treasury::get_stake_balance(&treasury);
            assert!(treasury_balance == MIN_STAKE, 2);

            // Return shared objects
            test::return_shared(pool);
            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = delegation_pool::E_INVALID_AMOUNT)]
    fun test_deposit_below_minimum() {
        let mut scenario = test::begin(ADMIN);
        setup_test(&mut scenario);

        test::next_tx(&mut scenario, USER);
        {
            let mut pool = test::take_shared<DelegationPool>(&scenario);
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let payment = mint_for_testing<SUI>(MIN_STAKE / 2, test::ctx(&mut scenario));

            delegation_pool::deposit(
                &mut pool,
                &mut registry,
                &mut treasury,
                &mut config,
                VALIDATOR,
                payment,
                test::ctx(&mut scenario)
            );

            test::return_shared(pool);
            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = stake::E_VALIDATOR_NOT_ACTIVE)]
    fun test_deposit_inactive_validator() {
        let mut scenario = test::begin(ADMIN);
        setup_test(&mut scenario);

        // Deactivate validator
        test::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);

            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                VALIDATOR,
                false, // inactive
                MAX_STAKE,
                1000,
                test::ctx(&mut scenario)
            );

            // Return shared object first
            test::return_shared(config);
            // Return admin cap with reference to scenario
            test::return_to_sender(&scenario, admin_cap);
        };

        test::next_tx(&mut scenario, USER);
        {
            let mut pool = test::take_shared<DelegationPool>(&scenario);
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let payment = mint_for_testing<SUI>(MIN_STAKE, test::ctx(&mut scenario));

            delegation_pool::deposit(
                &mut pool,
                &mut registry,
                &mut treasury,
                &mut config,
                VALIDATOR,
                payment,
                test::ctx(&mut scenario)
            );

            test::return_shared(pool);
            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = delegation_pool::E_POOL_FULL)]
    fun test_deposit_exceeds_validator_capacity() {
        let mut scenario = test::begin(ADMIN);
        setup_test(&mut scenario);

        test::next_tx(&mut scenario, USER);
        {
            let mut pool = test::take_shared<DelegationPool>(&scenario);
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let payment = mint_for_testing<SUI>(MAX_STAKE + MIN_STAKE, test::ctx(&mut scenario));

            delegation_pool::deposit(
                &mut pool,
                &mut registry,
                &mut treasury,
                &mut config,
                VALIDATOR,
                payment,
                test::ctx(&mut scenario)
            );

            test::return_shared(pool);
            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };
        test::end(scenario);
    }

    // Add a new test specifically for validator capacity
    #[test]
    #[expected_failure(abort_code = stake::E_STAKE_EXCEEDS_CAPACITY)]
    fun test_deposit_exceeds_validator_stake_limit() {
        let mut scenario = test::begin(ADMIN);
        setup_test(&mut scenario);

        // First update pool capacity to be higher than validator capacity
        test::next_tx(&mut scenario, ADMIN);
        {
            let mut pool = test::take_shared<DelegationPool>(&scenario);
            delegation_pool::update_capacity_for_testing(&mut pool, MAX_STAKE * 2);
            test::return_shared(pool);
        };

        test::next_tx(&mut scenario, USER);
        {
            let mut pool = test::take_shared<DelegationPool>(&scenario);
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let payment = mint_for_testing<SUI>(MAX_STAKE + MIN_STAKE, test::ctx(&mut scenario));

            delegation_pool::deposit(
                &mut pool,
                &mut registry,
                &mut treasury,
                &mut config,
                VALIDATOR,
                payment,
                test::ctx(&mut scenario)
            );

            test::return_shared(pool);
            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };
        test::end(scenario);
    }
}