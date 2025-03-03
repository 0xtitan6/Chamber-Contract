#[test_only]
module chamber::config_tests {
    // === SETUP ===
    use sui::test_scenario;
    use chamber::config::{Self, Config, AdminCap};

    // Test constants
    const ADMIN: address = @0xAD;
    const VALIDATOR: address = @0xCAFE;
    const NONEXISTENT_VALIDATOR: address = @0xDEAD;

    // Error constants for assertions
    const ERR_WRONG_MIN_STAKE: u64 = 0;
    const ERR_WRONG_MAX_STAKE: u64 = 1;
    const ERR_WRONG_PROTOCOL_FEE: u64 = 2;
    const ERR_WRONG_VALIDATOR_STATUS: u64 = 4;

    // === INITIALIZATION TESTS ===
    #[test]
    fun test_init_config() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        {
            config::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let config = test_scenario::take_shared<Config>(&scenario);
            
            assert!(!config::is_paused(&config), 0);
            assert!(config::get_min_stake(&config) == 1_000_000_000, ERR_WRONG_MIN_STAKE);
            assert!(config::get_max_stake(&config) == 1000 * 1_000_000_000, ERR_WRONG_MAX_STAKE);
            assert!(config::get_protocol_fee(&config) == 50, ERR_WRONG_PROTOCOL_FEE);
            assert!(config::get_total_staked(&config) == 0, 4);

            test_scenario::return_shared(config);

            let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            test_scenario::return_to_sender(&scenario, cap);
        };
        test_scenario::end(scenario);
    }

    // === PROTOCOL PARAMETER TESTS ===
    #[test]
    fun test_update_min_stake() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        {
            config::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<Config>(&scenario);
            let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            
            config::update_min_stake(&cap, &mut config, 2_000_000_000);
            assert!(config::get_min_stake(&config) == 2_000_000_000, ERR_WRONG_MIN_STAKE);

            test_scenario::return_to_sender(&scenario, cap);
            test_scenario::return_shared(config);
        };
        test_scenario::end(scenario);
    }

    // Test function
    #[test]
    fun test_update_max_stake() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        {
            config::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<Config>(&scenario);
            let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            
            // Initial max stake is 1000 * 1_000_000_000
            // Let's increase by 45% (4500 basis points) which is below the 50% limit
            let new_amount = 1450 * 1_000_000_000;
            
            config::update_max_stake(&cap, &mut config, new_amount, test_scenario::ctx(&mut scenario));
            assert!(config::get_max_stake(&config) == new_amount, ERR_WRONG_MAX_STAKE);

            test_scenario::return_to_sender(&scenario, cap);
            test_scenario::return_shared(config);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_update_protocol_fee() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        {
            config::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<Config>(&scenario);
            let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            
            config::update_protocol_fee(&cap, &mut config, 100, test_scenario::ctx(&mut scenario));
            assert!(config::get_protocol_fee(&config) == 100, ERR_WRONG_PROTOCOL_FEE);

            test_scenario::return_to_sender(&scenario, cap);
            test_scenario::return_shared(config);
        };
        test_scenario::end(scenario);
    }

    // === VALIDATOR MANAGEMENT TESTS ===
    #[test]
    fun test_add_validator() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        {
            config::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<Config>(&scenario);
            let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            
            config::add_or_update_validator(
                &cap,
                &mut config,
                VALIDATOR,
                true,
                1000 * 1_000_000_000,
                500,
                test_scenario::ctx(&mut scenario)
            );

            assert!(config::is_validator_active(&config, VALIDATOR, 0), ERR_WRONG_VALIDATOR_STATUS);
            let (is_active, max_stake, commission) = config::get_validator_config(&config, VALIDATOR);
            assert!(is_active == true, 1);
            assert!(max_stake == 1000 * 1_000_000_000, 2);
            assert!(commission == 500, 3);

            test_scenario::return_to_sender(&scenario, cap);
            test_scenario::return_shared(config);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_update_validator() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        {
            config::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        // First add the validator
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<Config>(&scenario);
            let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            
            config::add_or_update_validator(
                &cap,
                &mut config,
                VALIDATOR,
                true,
                1000 * 1_000_000_000,
                500,
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_to_sender(&scenario, cap);
            test_scenario::return_shared(config);
        };

        // Then update it
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<Config>(&scenario);
            let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            
            config::add_or_update_validator(
                &cap,
                &mut config,
                VALIDATOR,
                false,
                500 * 1_000_000_000,
                600,
                test_scenario::ctx(&mut scenario)
            );

            assert!(!config::is_validator_active(&config, VALIDATOR, 0), ERR_WRONG_VALIDATOR_STATUS);
            let (is_active, max_stake, commission) = config::get_validator_config(&config, VALIDATOR);
            assert!(!is_active, 1);
            assert!(max_stake == 500 * 1_000_000_000, 2);
            assert!(commission == 600, 3);

            test_scenario::return_to_sender(&scenario, cap);
            test_scenario::return_shared(config);
        };
        test_scenario::end(scenario);
    }

    // === SECURITY TESTS ===
    #[test]
    fun test_pause_functionality() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        {
            config::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<Config>(&scenario);
            let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            
            assert!(!config::is_paused(&config), 0);
            config::set_pause_status(&cap, &mut config, true);
            assert!(config::is_paused(&config), 1);

            test_scenario::return_to_sender(&scenario, cap);
            test_scenario::return_shared(config);
        };
        test_scenario::end(scenario);
    }

    // === TVL TRACKING TESTS ===
    #[test]
    fun test_total_staked_tracking() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        {
            config::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<Config>(&scenario);
            
            config::increase_total_staked(&mut config, 1_000_000_000);
            assert!(config::get_total_staked(&config) == 1_000_000_000, 0);

            config::decrease_total_staked(&mut config, 500_000_000);
            assert!(config::get_total_staked(&config) == 500_000_000, 1);

            test_scenario::return_shared(config);
        };
        test_scenario::end(scenario);
    }

    // === ERROR CASE TESTS ===
    #[test]
    #[expected_failure(abort_code = chamber::config::E_INVALID_PARAMETER)]
    fun test_invalid_min_stake() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        {
            config::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<Config>(&scenario);
            let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            
            config::update_min_stake(&cap, &mut config, 0);

            test_scenario::return_to_sender(&scenario, cap);
            test_scenario::return_shared(config);
        };
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = chamber::config::E_INVALID_PARAMETER)]
    fun test_invalid_protocol_fee() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        {
            config::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<Config>(&scenario);
            let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            
            config::update_protocol_fee(&cap, &mut config, 20000, test_scenario::ctx(&mut scenario));

            test_scenario::return_to_sender(&scenario, cap);
            test_scenario::return_shared(config);
        };
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = chamber::config::E_INVALID_PARAMETER)]
    fun test_invalid_validator_commission() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        {
            config::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<Config>(&scenario);
            let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            
            config::add_or_update_validator(
                &cap,
                &mut config,
                VALIDATOR,
                true,
                1000 * 1_000_000_000,
                20000,
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_to_sender(&scenario, cap);
            test_scenario::return_shared(config);
        };
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = chamber::config::E_VALIDATOR_NOT_FOUND)]
    fun test_nonexistent_validator_lookup() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        {
            config::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let config = test_scenario::take_shared<Config>(&scenario);
            
            let (_is_active, _max_stake, _commission) = 
                config::get_validator_config(&config, NONEXISTENT_VALIDATOR);

            test_scenario::return_shared(config);
        };
        test_scenario::end(scenario);
    }
}