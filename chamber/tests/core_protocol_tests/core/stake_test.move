#[test_only]
module chamber::stake_tests {
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::coin;
    use sui::sui::SUI;
    
    use chamber::stake::{Self, StakeRegistry};
    use chamber::config::{Self, Config, AdminCap};
    use chamber::treasury::{Self, Treasury};

    // Test constants
    const ADMIN: address = @0xAD;
    const USER1: address = @0x1;
    const VALIDATOR1: address = @0x42;

    // Error constants
    const E_BELOW_MINIMUM: u64 = 1;
    const E_STAKE_NOT_FOUND: u64 = 1;

    fun setup_test(): Scenario {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize modules
        next_tx(&mut scenario, ADMIN);
        {
            config::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, ADMIN);
        {
            treasury::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, ADMIN);
        {
            stake::init_for_testing(ctx(&mut scenario));
        };

        scenario
    }

    #[test]
    fun test_basic_stake() {
        let mut scenario = setup_test();
        
        // Setup validator
        next_tx(&mut scenario, ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_address<AdminCap>(&scenario, ADMIN);
            
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                VALIDATOR1,
                true,
                1000000000000,
                1000,
                test::ctx(&mut scenario)
            );
            
            test::return_shared(config);
            test::return_to_address(ADMIN, admin_cap);
        };

        // Test stake creation
        next_tx(&mut scenario, USER1);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            
            let stake_coin = coin::mint_for_testing<SUI>(100000000000, ctx(&mut scenario));
            
            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                VALIDATOR1,
                stake_coin,
                ctx(&mut scenario)
            );
            
            // Verify stake exists
            assert!(stake::has_stake(&registry, USER1), 0);
            
            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };
        
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = E_BELOW_MINIMUM, location = chamber::validation)]
    fun test_stake_below_minimum() {
        let mut scenario = setup_test();
        
        next_tx(&mut scenario, ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_address<AdminCap>(&scenario, ADMIN);
            
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                VALIDATOR1,
                true,
                1000000000000,
                1000,
                test::ctx(&mut scenario)
            );
            
            test::return_shared(config);
            test::return_to_address(ADMIN, admin_cap);
        };

        next_tx(&mut scenario, USER1);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            
            // Try to stake below minimum amount
            let stake_coin = coin::mint_for_testing<SUI>(100, ctx(&mut scenario));
            
            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                VALIDATOR1,
                stake_coin,
                ctx(&mut scenario)
            );
            
            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };
        
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = E_STAKE_NOT_FOUND, location = chamber::stake)]
    fun test_withdraw_without_stake() {
        let mut scenario = setup_test();
        
        next_tx(&mut scenario, USER1);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let config = test::take_shared<Config>(&scenario);
            
            // Create a test stake
            let stake = stake::create_stake_for_testing(
                VALIDATOR1,
                1000000,
                0,
                ctx(&mut scenario)
            );
            
            stake::withdraw(
                &mut registry,
                stake,
                &mut treasury,
                &config,
                ctx(&mut scenario)
            );
            
            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };
        
        test::end(scenario);
    }
}