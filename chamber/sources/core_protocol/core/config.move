/// Control panel of the entire protocol
module chamber::config {
    use sui::table::{Self, Table};
    use sui::event;

    const SYSTEM_CAPACITY: u64 = 100_000_000_000_000;

    /// Custom errors
    const E_INVALID_PARAMETER: u64 = 1;
    const E_VALIDATOR_NOT_FOUND: u64 = 2;
    const E_PROTOCOL_PAUSED: u64 = 3;
    const E_NOT_AUTHORIZED: u64 = 5;
    const E_RATE_LIMITED: u64 = 4;
    const E_CHANGE_TOO_LARGE: u64 = 6;
    const E_CAPACITY_EXCEEDED: u64 = 9;
    const E_NOT_EMERGENCY: u64 = 10;
    const E_ALREADY_IN_EMERGENCY: u64 = 11;

    // === Rate Limiting Constants ===
    const MIN_UPDATE_DELAY: u64 = 86400; // 24 hours in seconds
    const MAX_STAKE_CHANGE_PERCENTAGE: u64 = 5000; // 50% in basis points
    const MAX_FEE_CHANGE: u64 = 1000; // 10% in basis points

    /// Admin capability
    public struct AdminCap has key, store {
        id: UID,
        nonce: u64
    }

    /// Main configuration object
    public struct Config has key {
        id: UID,
        paused: bool,
        emergency_mode: bool,
        min_stake_amount: u64,
        max_stake_amount: u64,
        protocol_fee_bps: u64,
        withdrawal_delay: u64,
        validator_configs: Table<address, ValidatorConfig>,
        total_sui_staked: u64,
        last_fee_update: u64,
        last_stake_update: u64
    }

    /// Validator configuration
    public struct ValidatorConfig has store, drop {
        is_active: bool,
        max_stake: u64,
        commission_bps: u64,
        deactivation_epoch: u64
    }

    /// Events
    public struct ConfigUpdated has copy, drop {
        parameter_name: vector<u8>,
        old_value: u64,
        new_value: u64
    }

    public struct ValidatorStatusChanged has copy, drop {
        validator: address,
        is_active: bool
    }

    public struct EmergencyModeChanged has copy, drop {
        enabled: bool
    }

    /// Initialize module
    fun init(ctx: &mut TxContext) {
        let admin_cap = AdminCap {
            id: object::new(ctx),
            nonce: 42
        };

        let config = Config {
            id: object::new(ctx),
            paused: false,
            emergency_mode: false,
            min_stake_amount: 1_000_000_000,
            max_stake_amount: 1000 * 1_000_000_000,
            protocol_fee_bps: 50,
            withdrawal_delay: 172800,
            validator_configs: table::new(ctx),
            total_sui_staked: 0,
            last_fee_update: 0,
            last_stake_update: tx_context::epoch(ctx)
        };

        transfer::share_object(config);
        transfer::transfer(admin_cap, tx_context::sender(ctx));
    }

    // === Getter Functions ===
    
    public fun is_paused(config: &Config): bool {
        config.paused
    }

    public fun is_emergency_mode(config: &Config): bool {
        config.emergency_mode
    }

    public fun get_min_stake(config: &Config): u64 {
        config.min_stake_amount
    }

    public fun get_max_stake(config: &Config): u64 {
        config.max_stake_amount
    }

    public fun get_protocol_fee(config: &Config): u64 {
        config.protocol_fee_bps
    }

    public fun get_withdrawal_delay(config: &Config): u64 {
        config.withdrawal_delay
    }

    public fun get_validator_deactivation_epoch(config: &Config, validator: address): u64 {
        assert!(table::contains(&config.validator_configs, validator), E_VALIDATOR_NOT_FOUND);
        let validator_config = table::borrow(&config.validator_configs, validator);
        validator_config.deactivation_epoch
    }

    public fun get_total_staked(config: &Config): u64 {
        config.total_sui_staked
    }

    public fun check_system_capacity(config: &Config, amount: u64): bool {
        let total_staked = config.total_sui_staked;
        total_staked + amount > SYSTEM_CAPACITY
    }

    public fun get_validator_config(config: &Config, validator: address): (bool, u64, u64) {
        assert!(table::contains(&config.validator_configs, validator), E_VALIDATOR_NOT_FOUND);
        let config = table::borrow(&config.validator_configs, validator);
        (config.is_active, config.max_stake, config.commission_bps)
    }

    public fun is_validator_active(config: &Config, validator: address, current_epoch: u64): bool {
        if (table::contains(&config.validator_configs, validator)) {
            let validator_config = table::borrow(&config.validator_configs, validator);
            validator_config.is_active && 
            (validator_config.deactivation_epoch == 0 || 
            current_epoch < validator_config.deactivation_epoch)
        } else {
            false
        }
    }

    // === Setter Functions (Admin only) ===

    public entry fun set_pause_status(
        admin_cap: &AdminCap,
        config: &mut Config,
        paused: bool,
    ) {
        assert!(admin_cap.nonce == 42, E_NOT_AUTHORIZED);
        config.paused = paused;
    }

    public entry fun set_emergency_mode(
        admin_cap: &AdminCap,
        config: &mut Config,
        enabled: bool,
    ) {
        assert!(admin_cap.nonce == 42, E_NOT_AUTHORIZED);
        if (enabled) {
            assert!(!config.emergency_mode, E_ALREADY_IN_EMERGENCY);
            config.emergency_mode = true;
            config.paused = true;
            event::emit(EmergencyModeChanged { enabled: true });
        } else {
            config.emergency_mode = false;
            event::emit(EmergencyModeChanged { enabled: false });
            // System remains paused when exiting emergency mode
        };
    }

    public entry fun update_min_stake(
        admin_cap: &AdminCap,
        config: &mut Config,
        new_amount: u64,
    ) {
        assert!(admin_cap.nonce == 42, E_NOT_AUTHORIZED);
        assert!(!config.emergency_mode, E_NOT_EMERGENCY);
        assert!(new_amount > 0, E_INVALID_PARAMETER);
        assert!(new_amount <= config.max_stake_amount, E_INVALID_PARAMETER);
        
        let old_value = config.min_stake_amount;
        config.min_stake_amount = new_amount;
        event::emit(ConfigUpdated {
            parameter_name: b"min_stake_amount",
            old_value,
            new_value: new_amount
        });
    }

    public entry fun update_protocol_fee(
        admin_cap: &AdminCap,
        config: &mut Config,
        new_fee_bps: u64,
        ctx: &mut TxContext
    ) {
        assert!(admin_cap.nonce == 42, E_NOT_AUTHORIZED);
        assert!(!config.emergency_mode, E_NOT_EMERGENCY);
        assert!(new_fee_bps <= 10000, E_INVALID_PARAMETER);
        
        let current_time = tx_context::epoch(ctx);
        
        if (config.last_fee_update != 0 && current_time < config.last_fee_update + MIN_UPDATE_DELAY) {
            abort E_RATE_LIMITED
        };

        let fee_change: u64;
        if (new_fee_bps > config.protocol_fee_bps) {
            fee_change = new_fee_bps - config.protocol_fee_bps
        } else {
            fee_change = config.protocol_fee_bps - new_fee_bps
        };
        assert!(fee_change <= MAX_FEE_CHANGE, E_CHANGE_TOO_LARGE);

        let old_value = config.protocol_fee_bps;
        config.protocol_fee_bps = new_fee_bps;
        config.last_fee_update = current_time;
        
        event::emit(ConfigUpdated {
            parameter_name: b"protocol_fee_bps",
            old_value,
            new_value: new_fee_bps
        });
    }

    public entry fun update_max_stake(
        admin_cap: &AdminCap,
        config: &mut Config,
        new_amount: u64,
        ctx: &mut TxContext
    ) {
        
        assert!(admin_cap.nonce == 42, E_NOT_AUTHORIZED);
        assert!(!config.emergency_mode, E_NOT_EMERGENCY);
        assert!(new_amount >= config.min_stake_amount, E_INVALID_PARAMETER);
        
        let current_time = tx_context::epoch(ctx);
        
        if (config.last_stake_update != 0 && current_time < config.last_stake_update + MIN_UPDATE_DELAY) {
            abort E_RATE_LIMITED
        };
        
        let change_bps: u64;
        if (new_amount > config.max_stake_amount) {
            change_bps = ((new_amount - config.max_stake_amount) * 10000) / config.max_stake_amount
        } else {
            change_bps = ((config.max_stake_amount - new_amount) * 10000) / config.max_stake_amount
        };
        
        if (change_bps > MAX_STAKE_CHANGE_PERCENTAGE) {
            abort E_CHANGE_TOO_LARGE
        };
        
        let old_value = config.max_stake_amount;
        config.max_stake_amount = new_amount;
        config.last_stake_update = current_time;
       
        event::emit(ConfigUpdated {
            parameter_name: b"max_stake_amount",
            old_value,
            new_value: new_amount
        });
    }

    public entry fun update_withdrawal_delay(
        admin_cap: &AdminCap,
        config: &mut Config,
        new_delay: u64,
    ) {
        assert!(admin_cap.nonce == 42, E_NOT_AUTHORIZED);
        assert!(!config.emergency_mode, E_NOT_EMERGENCY);
        
        let old_value = config.withdrawal_delay;
        config.withdrawal_delay = new_delay;
        event::emit(ConfigUpdated {
            parameter_name: b"withdrawal_delay",
            old_value,
            new_value: new_delay
        });
    }

    // === Validator Management ===

    public entry fun add_or_update_validator(
        admin_cap: &AdminCap,
        config: &mut Config,
        validator: address,
        is_active: bool,
        max_stake: u64,
        commission_bps: u64,
        ctx: &mut TxContext
    ) {
        assert!(admin_cap.nonce == 42, E_NOT_AUTHORIZED);
        assert!(!config.emergency_mode, E_NOT_EMERGENCY);
        assert!(commission_bps <= 10000, E_INVALID_PARAMETER);

        let deactivation_epoch = if (is_active) {
            0
        } else {
            tx_context::epoch(ctx) + config.withdrawal_delay
        };
        
        let validator_config = ValidatorConfig {
            is_active,
            max_stake,
            commission_bps,
            deactivation_epoch
        };

        if (table::contains(&config.validator_configs, validator)) {
            table::remove(&mut config.validator_configs, validator);
        };
        
        table::add(&mut config.validator_configs, validator, validator_config);
        event::emit(ValidatorStatusChanged { validator, is_active });
    }

    // === Internal tracking functions ===

    public(package) fun increase_total_staked(config: &mut Config, amount: u64) {
        assert!(!config.paused, E_PROTOCOL_PAUSED);
        assert!(!config.emergency_mode, E_NOT_EMERGENCY);
        assert!(config.total_sui_staked + amount <= SYSTEM_CAPACITY, E_CAPACITY_EXCEEDED);
        
        config.total_sui_staked = config.total_sui_staked + amount;
    }

    public fun get_validator_commission(config: &Config, validator: address): u64 {
        if (table::contains(&config.validator_configs, validator)) {
            let validator_config = table::borrow(&config.validator_configs, validator);
            validator_config.commission_bps
        } else {
            0
        }
    }

    public(package) fun decrease_total_staked(config: &mut Config, amount: u64) {
        assert!(!config.paused || config.emergency_mode, E_PROTOCOL_PAUSED);
        config.total_sui_staked = config.total_sui_staked - amount;
    }

    // === Test-only functions ===

    #[test_only]
    public fun get_last_stake_update(config: &Config): u64 {
        config.last_stake_update
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }

    #[test_only]
    public fun create_admin_cap_for_testing(ctx: &mut TxContext): AdminCap {
        AdminCap {
            id: object::new(ctx),
            nonce: 0
        }
    }

    #[test_only]
    public fun reset_last_stake_update_for_testing(config: &mut Config, _ctx: &mut TxContext) {
        config.last_stake_update = 0;
    }

    #[test_only]
    public fun reset_last_fee_update_for_testing(config: &mut Config) {
        config.last_fee_update = 0;
    }

    #[test_only]
    public fun try_increase_total_staked(config: &mut Config, amount: u64): bool {
        if (config.paused || config.emergency_mode) {
            false
        } else {
            if (config.total_sui_staked + amount <= SYSTEM_CAPACITY) {
                config.total_sui_staked = config.total_sui_staked + amount;
                true
            } else {
                false
            }
        }
    }

    #[test_only]
    public fun get_epoch(ctx: &TxContext): u64 {
        tx_context::epoch(ctx)
    }
}