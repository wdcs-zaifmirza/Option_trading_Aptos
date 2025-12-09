module deployer_addr::options {
    
    // -- imports -- 
    use std::signer;  
    use std::vector;

    use aptos_framework::object::{Self,DeleteRef,TransferRef,ExtendRef,Object};
    use aptos_framework::event::{Self};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;

    // -- constants error codes --

    // object SEED 
    const NAME: vector<u8> = b"OpitonsConfigObjects";

    // option types
    const CALL_OPTION:u8 = 0;
    const PUT_OPTION:u8 = 1; 

    // option states
    const STATE_ACTIVE:u8 = 1;
    const STATE_EXPIRED:u8 = 2;
    const STATE_SETTLED:u8 = 3;
    const STATE_EXCERCISED:u8 = 4;

    // -- Error Codes --

    /// Invalid Option Type Chose Between Call and Put
    const E_INVALID_OPTION_TYPE: u64 = 11;
    /// Premium should be greater than Zero
    const E_INVALID_PREMIUM: u64 = 12;
    /// Invalid Amount
    const E_INVALID_AMOUNT: u64 = 13;
    /// Expiry Duration is Invalid check the min and max Duration
    const E_INVALID_EXPIRY_DURATION: u64 = 14;
    /// The Payment Amount is not enough to but option 
    const E_PAYMENT_NOT_ENOUGH: u64 = 15;
    /// Option state is not active
    const E_STATE_IS_NOT_ACTIVE: u64 = 16;
    /// The caller is not owner of the option
    const E_UNAUTHORISED: u64 = 17;
    /// The option is expired
    const E_OPTION_IS_EXPIRED: u64 = 18;
    /// The Option is not expired
    const E_OPTION_IS_NOT_EXPIRED: u64 = 18;
    /// The Option is not excercised
    const E_OPTION_NOT_EXERCISEABLE: u64 = 19;    
    
    
    
    // -- resources and objects --

    // 1. options config: deployer address .. confugration and maintaining the list of options.
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct OptionsConfig has key {
        admin: address,
        options_created: u64,
        options_addreses: vector<address>,
        min_expiry_sec: u64,
        max_expiry_sec: u64,
        extendRef:ExtendRef
    }

    // 2. option drtail: createor .. premium, amount , id , expiry timestamp.
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct OptionsDetails has key {
        id: u64,
        creator: address,
        premium: u64,
        amount: u64,
        creation_timestamp: u64,
        expiry_timestamp: u64,
        options_type: u8, // 0 for call & 1 for put
        option_state: u8,
        strike_price: u64,
        deleteRef: DeleteRef,
        transferRef: TransferRef
    }

    // 3. options vault: coin<Aptos Coin>.
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct OptionsVault has key {
        funds : Coin<AptosCoin>
    }

    // -- event and structs --
    
    // 1. create option 
    #[event]
    struct CreateOptionEvent has store,drop{
        creator: address,
        premium: u64,
        amount: u64,
        expiry_timestamp: u64,
        options_type: u8,
        strike_price: u64,
        option_addr : address, 
    }
    // 2. buy option 
    #[event]
    struct BuyOptionEvent has store,drop{
        buyer: address,
        payment_paid: u64,
        option_addr : address, 
    }
    // 3. excersised option 
    #[event]
    struct ExercisedOptionEvent has store,drop{
        option_addr : address, 
        caller : address,
        total_profit_raw : u64,
        price_at_exercised: u64,
    }
    // 4. settled option 
    #[event]
    struct SettleOptionEvent has store,drop{
        option_addr : address, 
        caller : address,
    }

    // -- entry functions and view fuctions -- 
    
    // 1. init_module
    entry fun init_module(deployer: &signer){
        let deployer_addr = signer::address_of(deployer);

        let constructor_ref = object::create_named_object(deployer,NAME);
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let object_signer = object::generate_signer(&constructor_ref);

        move_to(&object_signer,OptionsConfig{
            extendRef: extend_ref,
            admin: deployer_addr,
            options_created: 0,
            options_addreses: vector::empty<address>(),
            min_expiry_sec: 600,
            max_expiry_sec: 3600,
        });
    }

    // 2. create option public function
    public entry fun create_option(
        creator: &signer,
        premium: u64,
        amount: u64,
        expiry_timestamp: u64,
        options_type: u8,
        strike_price: u64,
        collatoral_amount: u64,
    ) {
        let creator_addr = signer::address_of(creator);
        let current_time = timestamp::now_seconds();

        // validation of input parameteres
        assert!(options_type == PUT_OPTION || options_type == CALL_OPTION ,E_INVALID_OPTION_TYPE);
        assert!(premium >= 0 ,E_INVALID_PREMIUM);
        assert!(amount >= 0 ,E_INVALID_AMOUNT);

        // validation of timestamps 

        // getting the address of config object 
        let config_object_address = object::create_object_address(&@deployer_addr, NAME);
        // getting the object by address
        let _config_object = object::address_to_object<OptionsConfig>(config_object_address);
        // a mutable refrence to the config resource
        let config = borrow_global_mut<OptionsConfig>(config_object_address);

        let expiry_duration = expiry_timestamp-current_time;
        assert!(expiry_duration >= config.min_expiry_sec && expiry_duration <= config.max_expiry_sec,);

        // create option details object
        let constructor_ref = object::create_object_from_account(creator);
        let transfer_ref = object::generate_transfer_ref(&constructor_ref);
        let delete_ref = object::generate_delete_ref(&constructor_ref);
        let object_signer = object::generate_signer(&constructor_ref);

        let option_id = config.options_created +    1;
        config.options_created = option_id;

        move_to(&object_signer, OptionsDetails{
            id: option_id,
            creator : creator_addr,
            premium,
            amount,
            creation_timestamp : timestamp::now_seconds(),
            expiry_timestamp,
            options_type,
            option_state: STATE_ACTIVE,
            strike_price,
            deleteRef: delete_ref,
            transferRef: transfer_ref

        });

        let collatoral_funds = coin::withdraw<AptosCoin>(creator, collatoral_amount); 

        move_to(&object_signer, OptionsVault{
            funds: collatoral_funds,
        });

        let option_addr = object::address_from_constructor_ref(&constructor_ref);
        config.options_addreses.push_back(option_addr);

        // event emitting
        event::emit(CreateOptionEvent{
            amount,
            creator:creator_addr,
            premium,
            expiry_timestamp,
            options_type,
            strike_price,
            option_addr,
        });
    }   

    // 3. Buy Option
    public entry fun buy_option(
        buyer : &signer,
        option_object : Object<OptionsDetails>,
        payment_amount : u64,
    ) {
        let buyer_addr = signer::address_of(buyer);
        let option_addr = object::object_address<OptionsDetails>(&option_object);
        let option = borrow_global_mut<OptionsDetails>(option_addr);

        assert!(payment_amount == option.premium,E_PAYMENT_NOT_ENOUGH);
        assert!(option.option_state == STATE_ACTIVE , E_STATE_IS_NOT_ACTIVE);

        let payment_fund = coin::withdraw<AptosCoin>(buyer, payment_amount);
        let vault = borrow_global_mut<OptionsVault>(option_addr);

        coin::merge(&mut vault.funds, payment_fund);

        let transfer_ref = &option.transferRef;
        let linear_transfer_ref = object::generate_linear_transfer_ref(transfer_ref);


        object::transfer_with_ref(linear_transfer_ref,buyer_addr);

        // emitting event
        event::emit(BuyOptionEvent{
            buyer:buyer_addr,
            payment_paid:payment_amount,
            option_addr
        });
    }

    // 4. excercise option  
    public entry fun exercise_option(
        caller : &signer,
        option_obj : Object<OptionsDetails>,
        payment_amount: u64,
    ){
        let caller_addr = signer::address_of(caller);
        let option_addr = object::object_address(&option_obj);

        assert!(object::owner(option_obj) == caller_addr, E_UNAUTHORISED);

        let option = borrow_global_mut<OptionsDetails>(option_addr);
        assert!(option.option_state == STATE_ACTIVE , E_STATE_IS_NOT_ACTIVE);

        let current_time = timestamp::now_seconds();
        assert!(option.expiry_timestamp > current_time , E_OPTION_IS_EXPIRED);

        // fetch the current price of the option (btc/usd) from oracle
        let current_price = get_current_price();

        let is_in_money = false;
        let profit_per_unit = 0;

        if(option.options_type == CALL_OPTION){
            
            if(option.strike_price < current_price){
                is_in_money = true;
                profit_per_unit = current_price - option.strike_price;
            }

        } else {

            if(option.strike_price > current_price){
                is_in_money = true;
                profit_per_unit = current_price - option.strike_price;
            }

        };

        assert!(is_in_money , E_OPTION_NOT_EXERCISEABLE);

        // transfer of strike price + profit
        let vault = borrow_global_mut<OptionsVault>(option_addr);
        let total_profit_raw = aptos_std::math64::mul_div(profit_per_unit as u64, option.amount, 100000000);

        if (option.options_type == CALL_OPTION) {
            let strike_cost = option.strike_price * option.amount / 100000000 ;
            assert!(payment_amount > strike_cost , E_INVALID_AMOUNT);

            let payment_coins = coin::withdraw<AptosCoin>(caller, payment_amount);
            coin::merge(&mut vault.funds, payment_coins);

            let profit_coins = coin::extract(&mut vault.funds, total_profit_raw);
            coin::deposit(caller_addr, profit_coins);

        } else {

            let profit_coins = coin::extract(&mut vault.funds, total_profit_raw);
            coin::deposit(caller_addr, profit_coins);
        
        };

        option.option_state = STATE_EXCERCISED;

        // emitting event
        event::emit(ExercisedOptionEvent{
            option_addr,
            caller: caller_addr,
            total_profit_raw,
            price_at_exercised: current_price,
        });
    }


    public entry fun settle_expired_option(
        caller : &signer,
        option_obj : Object<OptionsDetails>
    ){
        let caller_addr = signer::address_of(caller);
        let option_addr = object::object_address(&option_obj);
        let option = borrow_global_mut<OptionsDetails>(option_addr);

        assert!(object::owner(option_obj) == caller_addr || option.creator == caller_addr, E_UNAUTHORISED);

        let current_time = timestamp::now_seconds();
        assert!(option.expiry_timestamp < current_time , E_OPTION_IS_NOT_EXPIRED);

        option.option_state = STATE_EXPIRED;

        // if caller is creator get all funds back 
        if(option.creator == caller_addr){
            let vault = borrow_global_mut<OptionsVault>(option_addr);
            let all_funds = coin::extract_all(&mut vault.funds);
            coin::deposit(caller_addr,all_funds);
        };

        // emitting event 
        event::emit(SettleOptionEvent{
            option_addr,
            caller: caller_addr,
        });
    }
}