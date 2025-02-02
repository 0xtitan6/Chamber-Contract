module chamber::csui {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::event;
    use sui::clock::{Self, Clock};

    /// The cSUI token type
    public struct CSUI has drop {}

    /// Admin capability for managing the token
    public struct AdminCap has key, store {
        id: UID
    }

    /// Capability for authorized minting
    public struct MinterCap has key, store {
        id: UID
    }

    /// Token metadata for indexing and display
    public struct TokenMetadata has key, store {
        id: UID,
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
        icon_url: Option<vector<u8>>,
        project_url: Option<vector<u8>>
    }

    /// Events
    public struct MintEvent has copy, drop {
        amount: u64,
        recipient: address,
        timestamp: u64
    }

    public struct BurnEvent has copy, drop {
        amount: u64,
        sender: address,
        timestamp: u64
    }

    /// Error codes
    const E_ZERO_AMOUNT: u64 = 2;
    const E_MAX_SUPPLY_EXCEEDED: u64 = 3;

    /// Supply constants
    const MAX_SUPPLY: u64 = 1_000_000_000_000_000;  // 1 quadrillion units (with 9 decimals)

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(CSUI {}, ctx)
    }

    fun init(witness: CSUI, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            witness,
            9,
            b"cSUI",
            b"Chamber SUI",
            b"Liquid staking token for SUI",
            option::none(),
            ctx
        );

        // Initialize metadata
        let token_metadata = TokenMetadata {
            id: object::new(ctx),
            name: b"Chamber SUI",
            symbol: b"cSUI",
            decimals: 9,
            icon_url: option::none(),
            project_url: option::none()
        };

        // Create admin capability
        let admin_cap = AdminCap {
            id: object::new(ctx)
        };

        // Create initial minter capability
        let minter_cap = MinterCap {
            id: object::new(ctx)
        };

        // Transfer objects
        transfer::share_object(token_metadata);
        transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
        transfer::public_transfer(metadata, tx_context::sender(ctx));
        transfer::public_transfer(admin_cap, tx_context::sender(ctx));
        transfer::public_transfer(minter_cap, tx_context::sender(ctx));
    }

    /// Mint new cSUI tokens (only authorized minters)
    public fun mint(
        treasury_cap: &mut TreasuryCap<CSUI>,
        _minter_cap: &MinterCap,
        amount: u64,
        recipient: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(amount > 0, E_ZERO_AMOUNT);
        
        // Safety check for maximum supply
        let current_supply = coin::total_supply(treasury_cap);
        assert!(current_supply + amount <= MAX_SUPPLY, E_MAX_SUPPLY_EXCEEDED);
        
        let tokens = coin::mint(treasury_cap, amount, ctx);
        transfer::public_transfer(tokens, recipient);

        event::emit(MintEvent {
            amount,
            recipient,
            timestamp: clock::timestamp_ms(clock)
        });
    }

    /// Burn cSUI tokens
    public fun burn(
        treasury_cap: &mut TreasuryCap<CSUI>,
        tokens: Coin<CSUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let amount = coin::value(&tokens);
        let sender = tx_context::sender(ctx);

        coin::burn(treasury_cap, tokens);

        event::emit(BurnEvent {
            amount,
            sender,
            timestamp: clock::timestamp_ms(clock)
        });
    }

    /// Split a coin into two
    public fun split(
        self: &mut Coin<CSUI>,
        split_amount: u64,
        ctx: &mut TxContext
    ): Coin<CSUI> {
        coin::split(self, split_amount, ctx)
    }

    /// Merge two coins
    public fun join(self: &mut Coin<CSUI>, other: Coin<CSUI>) {
        coin::join(self, other)
    }

    /// Create new minter capability
    public entry fun create_minter(
        _: &AdminCap,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let minter_cap = MinterCap {
            id: object::new(ctx)
        };
        transfer::public_transfer(minter_cap, recipient);
    }

    /// Revoke minter capability
    public entry fun revoke_minter(
        _: &AdminCap,
        _minter_cap: MinterCap
    ) {
        let MinterCap { id } = _minter_cap;
        object::delete(id);
    }

    /// Update token metadata
    public entry fun update_metadata(
        _: &AdminCap,
        metadata: &mut TokenMetadata,
        name: vector<u8>,
        symbol: vector<u8>,
        icon_url: Option<vector<u8>>,
        project_url: Option<vector<u8>>
    ) {
        metadata.name = name;
        metadata.symbol = symbol;
        metadata.icon_url = icon_url;
        metadata.project_url = project_url;
    }

    /// Get coin metadata
    public fun get_metadata(metadata: &TokenMetadata): (vector<u8>, vector<u8>, u8) {
        (metadata.name, metadata.symbol, metadata.decimals)
    }

    /// Get the balance of a coin
    public fun balance(coin: &Coin<CSUI>): u64 {
        coin::value(coin)
    }

    /// Get total supply
    public fun total_supply(treasury_cap: &TreasuryCap<CSUI>): u64 {
        coin::total_supply(treasury_cap)
    }

    // Test helper functions
    #[test_only]
    public fun init_test_token(ctx: &mut TxContext) {
        init(CSUI {}, ctx)
    }

    #[test_only]
    public fun mint_for_testing(
        treasury_cap: &mut TreasuryCap<CSUI>,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let tokens = coin::mint(treasury_cap, amount, ctx);
        transfer::public_transfer(tokens, recipient);
    }

    #[test_only]
    public fun create_treasury_cap_for_testing(ctx: &mut TxContext): TreasuryCap<CSUI> {
        let (treasury_cap, metadata) = coin::create_currency(
            CSUI {},
            9,
            b"cSUI",
            b"Chamber SUI",
            b"Liquid staking token for SUI",
            option::none(),
            ctx
        );
        transfer::public_transfer(metadata, tx_context::sender(ctx));
        treasury_cap
    }
}