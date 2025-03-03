#[test_only]
module chamber::csui_tests {
    use sui::test_scenario::{Self as test, next_tx, ctx};
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::clock::{Self};
    
    use chamber::csui::{Self, CSUI, AdminCap, MinterCap, TokenMetadata};

    // Test constants
    const ADMIN: address = @0xAD;
    const USER1: address = @0x1;
    const MINTER: address = @0x3;
    
    const MINT_AMOUNT: u64 = 1000000000; // 1 cSUI
    const INITIAL_SUPPLY: u64 = 0;

    // Error constants for testing
    const E_WRONG_SUPPLY: u64 = 1;
    const E_WRONG_BALANCE: u64 = 2;
    const E_CAP_EXISTS: u64 = 3;
    const E_METADATA_MISMATCH: u64 = 4;

    #[test]
    fun test_init_module() {
        let mut scenario = test::begin(ADMIN);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Test module initialization
        {
            csui::init_test_token(ctx(&mut scenario));
            next_tx(&mut scenario, ADMIN);
            
            // Verify admin capabilities were created
            assert!(test::has_most_recent_for_address<AdminCap>(ADMIN), E_CAP_EXISTS);
            assert!(test::has_most_recent_for_address<MinterCap>(ADMIN), E_CAP_EXISTS);
            
            // Verify metadata was created correctly
            let metadata = test::take_shared<TokenMetadata>(&scenario);
            let (name, symbol, decimals) = csui::get_metadata(&metadata);
            assert!(name == b"Chamber SUI", E_METADATA_MISMATCH);
            assert!(symbol == b"cSUI", E_METADATA_MISMATCH);
            assert!(decimals == 9, E_METADATA_MISMATCH);
            test::return_shared(metadata);
        };

        // Verify initial supply is 0
        next_tx(&mut scenario, ADMIN);
        {
            let treasury_cap = test::take_from_address<TreasuryCap<CSUI>>(&scenario, ADMIN);
            assert!(csui::total_supply(&treasury_cap) == INITIAL_SUPPLY, E_WRONG_SUPPLY);
            test::return_to_address(ADMIN, treasury_cap);
        };

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    fun test_basic_mint_burn() {
        let mut scenario = test::begin(ADMIN);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Initialize module
        csui::init_test_token(ctx(&mut scenario));
        
        // Test minting
        next_tx(&mut scenario, ADMIN);
        {
            let mut treasury_cap = test::take_from_address<TreasuryCap<CSUI>>(&scenario, ADMIN);
            let minter_cap = test::take_from_address<MinterCap>(&scenario, ADMIN);
            
            csui::mint(&mut treasury_cap, &minter_cap, MINT_AMOUNT, USER1, &clock, ctx(&mut scenario));
            
            assert!(csui::total_supply(&treasury_cap) == MINT_AMOUNT, E_WRONG_SUPPLY);
            
            test::return_to_address(ADMIN, treasury_cap);
            test::return_to_address(ADMIN, minter_cap);
        };

        // Test burning
        next_tx(&mut scenario, USER1);
        {
            let coin = test::take_from_address<Coin<CSUI>>(&scenario, USER1);
            assert!(coin::value(&coin) == MINT_AMOUNT, E_WRONG_BALANCE);
            
            let mut treasury_cap = test::take_from_address<TreasuryCap<CSUI>>(&scenario, ADMIN);
            csui::burn(&mut treasury_cap, coin, &clock, ctx(&mut scenario));
            
            assert!(csui::total_supply(&treasury_cap) == 0, E_WRONG_SUPPLY);
            test::return_to_address(ADMIN, treasury_cap);
        };

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    fun test_split_join() {
        let mut scenario = test::begin(ADMIN);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Initialize module
        csui::init_test_token(ctx(&mut scenario));
        
        // Mint tokens
        next_tx(&mut scenario, ADMIN);
        {
            let mut treasury_cap = test::take_from_address<TreasuryCap<CSUI>>(&scenario, ADMIN);
            let minter_cap = test::take_from_address<MinterCap>(&scenario, ADMIN);
            csui::mint(&mut treasury_cap, &minter_cap, MINT_AMOUNT, USER1, &clock, ctx(&mut scenario));
            test::return_to_address(ADMIN, treasury_cap);
            test::return_to_address(ADMIN, minter_cap);
        };
        
        // Test split and join
        next_tx(&mut scenario, USER1);
        {
            let mut coin = test::take_from_address<Coin<CSUI>>(&scenario, USER1);
            let split_amount = MINT_AMOUNT / 2;
            
            let split_coin = csui::split(&mut coin, split_amount, ctx(&mut scenario));
            assert!(coin::value(&coin) == split_amount, E_WRONG_BALANCE);
            assert!(coin::value(&split_coin) == split_amount, E_WRONG_BALANCE);
            
            // Test join
            csui::join(&mut coin, split_coin);
            assert!(coin::value(&coin) == MINT_AMOUNT, E_WRONG_BALANCE);
            
            test::return_to_address(USER1, coin);
        };

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    fun test_minter_management() {
        let mut scenario = test::begin(ADMIN);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Initialize module
        csui::init_test_token(ctx(&mut scenario));
        
        // Test creating new minter
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_address<AdminCap>(&scenario, ADMIN);
            csui::create_minter(&admin_cap, MINTER, ctx(&mut scenario));
            test::return_to_address(ADMIN, admin_cap);
        };

        // Verify new minter can mint
        next_tx(&mut scenario, MINTER);
        {
            let mut treasury_cap = test::take_from_address<TreasuryCap<CSUI>>(&scenario, ADMIN);
            let minter_cap = test::take_from_address<MinterCap>(&scenario, MINTER);
            
            csui::mint(&mut treasury_cap, &minter_cap, MINT_AMOUNT, USER1, &clock, ctx(&mut scenario));
            
            test::return_to_address(ADMIN, treasury_cap);
            test::return_to_address(MINTER, minter_cap);
        };

        // Test revoking minter
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_address<AdminCap>(&scenario, ADMIN);
            let minter_cap = test::take_from_address<MinterCap>(&scenario, MINTER);
            
            csui::revoke_minter(&admin_cap, minter_cap);
            test::return_to_address(ADMIN, admin_cap);
        };

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    fun test_metadata_updates() {
        let mut scenario = test::begin(ADMIN);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Initialize module
        csui::init_test_token(ctx(&mut scenario));
        
        // Test metadata updates
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_address<AdminCap>(&scenario, ADMIN);
            let mut metadata = test::take_shared<TokenMetadata>(&scenario);
            
            let new_name = b"Updated cSUI";
            let new_symbol = b"cSUI_v2";
            let new_icon = option::some(b"new_icon_url");
            let new_url = option::some(b"new_project_url");
            
            csui::update_metadata(
                &admin_cap, 
                &mut metadata, 
                new_name, 
                new_symbol,
                new_icon,
                new_url
            );
            
            let (name, symbol, _) = csui::get_metadata(&metadata);
            assert!(name == new_name, E_METADATA_MISMATCH);
            assert!(symbol == new_symbol, E_METADATA_MISMATCH);
            
            test::return_to_address(ADMIN, admin_cap);
            test::return_shared(metadata);
        };

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
}