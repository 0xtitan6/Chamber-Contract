#[test_only]
module chamber::cross_state_tests {
    use sui::test_scenario::{Self as test, Scenario};
    use sui::test_utils::{assert_eq, Self as test_utils};
    use sui::coin::{Self};
    use sui::sui::SUI;
    
    use chamber::delegation_pool::{Self, DelegationPool};
    use chamber::stake::{Self, StakeRegistry};
    use chamber::treasury::{Self, Treasury};
    use chamber::config::{Self, Config, AdminCap};
    use chamber::position_manager::{Self, PositionManager};
    use chamber::restake_manager::{Self, RestakeManager};
    use chamber::restake_strategy::{Self};
    use chamber::restake_vault::{Self, RestakeVault};
    use chamber::exchange::{Self,ExchangeRate};

    // Test addresses
    const TEST_ADMIN: address = @0x1234;
    const TEST_VALIDATOR: address = @0x5678;
    const ALICE: address = @0x1111;
    
    // Test amounts
    const INITIAL_STAKE: u64 = 1000 * 1_000_000_000; // 1000 SUI
    const MAX_VALIDATOR_STAKE: u64 = 10000 * 1_000_000_000; // 10000 SUI
    const REWARD_AMOUNT: u64 = 100 * 1_000_000_000; // 100 SUI
    const RATE_PRECISION: u64 = 1_000_000_000;
    const STAKE_AMOUNT: u64 = 1_000_000_000;
    
    fun setup_test(scenario: &mut Scenario) {
        test::next_tx(scenario, TEST_ADMIN);
        {
            // Core module initializations
            config::init_for_testing(test::ctx(scenario));
            stake::init_for_testing(test::ctx(scenario));
            treasury::init_for_testing(test::ctx(scenario));
            exchange::init_for_testing(test::ctx(scenario));
            //rewards::init_for_testing(test::ctx(scenario));  // Add rewards initialization
            
            // Pool and manager initializations
            delegation_pool::init_for_testing(test::ctx(scenario));
            position_manager::init_for_testing(test::ctx(scenario));
            
            // Restake related initializations
            restake_vault::init_for_testing(test::ctx(scenario));
            restake_manager::init_for_testing(test::ctx(scenario));
            restake_strategy::init_for_testing(test::ctx(scenario));
        };

        // Verify RestakeManager was created
        test::next_tx(scenario, TEST_ADMIN);
        {
            let manager = test::take_shared<RestakeManager>(scenario);
            test::return_shared(manager);
        };

        // Set up validator configuration
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

    #[test]
    /// Test treasury and registry balance consistency
    fun test_treasury_registry_balance_consistency() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);
        
        // Simulate stake deposits
        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            
            let payment = coin::mint_for_testing<SUI>(INITIAL_STAKE, test::ctx(&mut scenario));

            // Perform stake operation
            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                payment,
                test::ctx(&mut scenario)
            );
            
            // Verify consistency
            let treasury_balance = treasury::get_stake_balance(&treasury);
            let registry_total = stake::get_validator_stake(&registry, TEST_VALIDATOR);
            assert_eq(treasury_balance, registry_total);
            
            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };
        test::end(scenario);
    }

    #[test]
    /// Test config and treasury state alignment
    fun test_config_treasury_state_alignment() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);
        
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            
            // Update fee configuration
            config::update_protocol_fee(
                &admin_cap,
                &mut config,
                100, // 1% fee
                test::ctx(&mut scenario)
            );
            
            // Verify treasury alignment with config
            let treasury_fee = treasury::get_protocol_fees(&treasury);
            assert_eq(treasury_fee, 0); // No fees collected yet
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(treasury);
            test::return_shared(config);
        };
        test::end(scenario);
    }

    #[test]
    /// Test validator state synchronization
    fun test_validator_state_synchronization() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);
        
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            
            // Add a validator
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                true,
                MAX_VALIDATOR_STAKE,
                1000,
                test::ctx(&mut scenario)
            );
            
            // Verify validator is active
            assert!(config::is_validator_active(&config, TEST_VALIDATOR, 0), 0);
            
            // Deactivate validator
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                false,
                MAX_VALIDATOR_STAKE,
                1000,
                test::ctx(&mut scenario)
            );
            
            // Verify validator is inactive
            assert!(!config::is_validator_active(&config, TEST_VALIDATOR, 0), 1);
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };
        test::end(scenario);
    }

    #[test]
    /// Test user stake record accuracy
    fun test_user_stake_record_accuracy() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);
        
        // Simulate stake operations
        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            
            let payment = coin::mint_for_testing<SUI>(INITIAL_STAKE, test::ctx(&mut scenario));
            
            // Perform stake operation
            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                payment,
                test::ctx(&mut scenario)
            );
            
            // Verify user stake record
            let total_staked = treasury::get_stake_balance(&treasury);
            assert_eq(total_staked, INITIAL_STAKE);
            
            // Verify registry records
            let validator_stake = stake::get_validator_stake(&registry, TEST_VALIDATOR);
            assert_eq(validator_stake, INITIAL_STAKE);
            
            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };
        test::end(scenario);
    }

    #[test]
    /// Test complete stake flow with all modules
    fun test_complete_stake_flow() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);
        
        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            
            let payment = coin::mint_for_testing<SUI>(INITIAL_STAKE, test::ctx(&mut scenario));
            
            // 1. Perform stake
            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                payment,
                test::ctx(&mut scenario)
            );
            
            // 2. Verify complete system state
            let treasury_balance = treasury::get_stake_balance(&treasury);
            let registry_total = stake::get_validator_stake(&registry, TEST_VALIDATOR);
            let config_total = config::get_total_staked(&config);
            
            assert_eq(treasury_balance, INITIAL_STAKE);
            assert_eq(registry_total, INITIAL_STAKE);
            assert_eq(config_total, INITIAL_STAKE);
            
            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };
        test::end(scenario);
    }

    #[test]
    fun test_exchange_rate_updates() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);
        
        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let mut exchange_rate = test::take_shared<ExchangeRate>(&scenario);
            
            // Record initial rate (should be 1:1)
            let initial_rate = exchange::get_rate(&exchange_rate);
            assert_eq(initial_rate, RATE_PRECISION);
            let initial_total_sui = exchange::get_total_sui(&exchange_rate);
            assert_eq(initial_total_sui, 0);
            
            // Perform stake
            let payment = coin::mint_for_testing<SUI>(INITIAL_STAKE, test::ctx(&mut scenario));
            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                payment,
                test::ctx(&mut scenario)
            );
            
            // Update exchange rate 
            exchange::update_rate_stake(
                &mut exchange_rate,
                INITIAL_STAKE,
                test::ctx(&mut scenario)
            );
            
            // Verify totals updated
            let new_total_sui = exchange::get_total_sui(&exchange_rate);
            assert_eq(new_total_sui, INITIAL_STAKE);
            
            // Process rewards
            test::next_tx(&mut scenario, TEST_ADMIN);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let reward_payment = coin::mint_for_testing<SUI>(REWARD_AMOUNT, test::ctx(&mut scenario));
            
            let (validator_rewards, protocol_fees) = treasury::distribute_rewards(
                &admin_cap,
                &mut treasury,
                &config,
                TEST_VALIDATOR,
                REWARD_AMOUNT,
                test::ctx(&mut scenario)
            );
            
            // Clean up coins
            test_utils::destroy(reward_payment);
            transfer::public_transfer(validator_rewards, TEST_VALIDATOR);
            transfer::public_transfer(protocol_fees, TEST_ADMIN);
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
            test::return_shared(exchange_rate);
        };
        test::end(scenario);
    }

    #[test]
    fun test_exchange_rate_updates_after_rewards() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);
        
        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let mut exchange_rate = test::take_shared<ExchangeRate>(&scenario);
            
            // Initial stake
            let payment = coin::mint_for_testing<SUI>(INITIAL_STAKE, test::ctx(&mut scenario));
            
            // Record initial state
            let initial_rate = exchange::get_rate(&exchange_rate);
            let initial_total_sui = exchange::get_total_sui(&exchange_rate);
            
            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                payment,
                test::ctx(&mut scenario)
            );

            // Update exchange rate after stake
            exchange::update_rate_stake(
                &mut exchange_rate,
                INITIAL_STAKE,
                test::ctx(&mut scenario)
            );

            // Process rewards
            test::next_tx(&mut scenario, TEST_ADMIN);
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let reward_payment = coin::mint_for_testing<SUI>(REWARD_AMOUNT, test::ctx(&mut scenario));
            
            let (validator_rewards, protocol_fees) = treasury::distribute_rewards(
                &admin_cap,
                &mut treasury,
                &config,
                TEST_VALIDATOR,
                REWARD_AMOUNT,
                test::ctx(&mut scenario)
            );

            let validator_reward_value = coin::value(&validator_rewards);
            let protocol_fees_value = coin::value(&protocol_fees);

            // Update exchange rate after rewards
            exchange::update_rate_rewards(
                &mut exchange_rate,
                validator_reward_value + protocol_fees_value,
                test::ctx(&mut scenario)
            );
            
            // Verify final state
            let final_rate = exchange::get_rate(&exchange_rate);
            let final_total_sui = exchange::get_total_sui(&exchange_rate);
            
            assert!(final_rate > initial_rate, 0);
            assert!(final_total_sui > initial_total_sui, 1);
            
            // Clean up
            test_utils::destroy(reward_payment);
            transfer::public_transfer(validator_rewards, TEST_VALIDATOR);
            transfer::public_transfer(protocol_fees, TEST_ADMIN);
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
            test::return_shared(exchange_rate);
        };
        test::end(scenario);
    }

    #[test]
    fun test_delegation_pool_stake_consistency() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        test::next_tx(&mut scenario, ALICE);
        {
            let mut pool = test::take_shared<DelegationPool>(&scenario);
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let payment = coin::mint_for_testing<SUI>(STAKE_AMOUNT, test::ctx(&mut scenario));
            
            // Make basic delegation pool deposit with all required parameters
            delegation_pool::deposit(
                &mut pool,
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,  // Using TEST_VALIDATOR from constants
                payment,
                test::ctx(&mut scenario)
            );

            // Verify pool state
            let pool_balance = delegation_pool::get_total_sui_staked(&pool);
            let registry_stake = stake::get_validator_stake(&registry, TEST_VALIDATOR);
            let treasury_balance = treasury::get_stake_balance(&treasury);

            assert_eq(pool_balance, registry_stake);
            assert_eq(registry_stake, treasury_balance);
            assert_eq(pool_balance, STAKE_AMOUNT);

            test::return_shared(pool);
            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };
        test::end(scenario);
    }

    #[test]
    fun test_integrated_delegation_flow() {
        let mut scenario = test::begin(TEST_ADMIN);
        setup_test(&mut scenario);

        test::next_tx(&mut scenario, ALICE);
        {
            // Take objects in dependency order
            let mut config = test::take_shared<Config>(&scenario);
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut pool = test::take_shared<DelegationPool>(&scenario);
            let mut restake_manager = test::take_shared<RestakeManager>(&scenario);
            let mut position_manager = test::take_shared<PositionManager>(&scenario);
            let mut vault = test::take_shared<RestakeVault>(&scenario);

            // First setup restake type
            restake_manager::create_restake_type(
                &mut restake_manager,
                true,
                1_000_000_000,
                MAX_VALIDATOR_STAKE,
                500,
                1,
                test::ctx(&mut scenario)
            );

            // Create position
            position_manager::create_position(
                &mut position_manager,
                STAKE_AMOUNT,
                1,
                100,
                test::ctx(&mut scenario)
            );

            // Make pool deposit
            let payment = coin::mint_for_testing<SUI>(STAKE_AMOUNT, test::ctx(&mut scenario));
            let vault_payment = coin::mint_for_testing<SUI>(STAKE_AMOUNT, test::ctx(&mut scenario));
            
            delegation_pool::deposit(
                &mut pool,
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                payment,
                test::ctx(&mut scenario)
            );

            // Store in vault
            restake_vault::deposit_for_testing(
                &mut vault,
                vault_payment,
                TEST_VALIDATOR,
                test::ctx(&mut scenario)
            );

            // Verifications...

            // Return objects in reverse order
            test::return_shared(vault);
            test::return_shared(position_manager);
            test::return_shared(restake_manager);
            test::return_shared(pool);
            test::return_shared(treasury);
            test::return_shared(registry);
            test::return_shared(config);
        };
        test::end(scenario);
    }
}